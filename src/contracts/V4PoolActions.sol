// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "..//types/Currency.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {Position} from "../libraries/Position.sol";
import {StateLibrary} from "../libraries/StateLibrary.sol";
import {TransientStateLibrary} from "../libraries/TransientStateLibrary.sol";
import {TickMath} from "../libraries/TickMath.sol";

import {DeltaResolver} from "./base/DeltaResolver.sol";
import {BaseActionsRouter} from "./base/BaseActionsRouter.sol";
import {Actions} from "../libraries/Actions.sol";
import {CalldataDecoder} from "../libraries/CalldataDecoder.sol";
import {SlippageCheck} from "../libraries/SlippageCheck.sol";
import {PositionInfo, PositionInfoLibrary} from "../libraries/PositionInfoLibrary.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import {NativeWrapper} from "./base/NativeWrapper.sol";
import {IWETH9} from "../interfaces/external/IWETH9.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {PathKey} from "../libraries/PathKey.sol";
import {IV4Router} from "../interfaces/IV4Router.sol";
import {ActionConstants} from "../libraries/ActionConstants.sol";
import {BipsLibrary} from "../libraries/BipsLibrary.sol";

/// @title UniswapV4Router
/// @notice Abstract contract that contains all internal logic needed for routing through Uniswap v4 pools
/// @dev the entry point to executing actions in this contract is calling `BaseActionsRouter._executeActions`
/// An inheriting contract should call _executeActions at the point that they wish actions to be executed
abstract contract V4PoolActions is IV4Router, BaseActionsRouter, DeltaResolver {
    using SafeCast for *;
    using BipsLibrary for uint256;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using CalldataDecoder for bytes;
    using SlippageCheck for BalanceDelta;

    mapping(uint256 => PositionInfo info) public positionInfo;
    mapping(bytes25 poolId => PoolKey poolKey) public poolKeys;

    function _handleAction(
        uint256 action,
        bytes calldata params
    ) internal override {
        // swap actions and payment actions in different blocks for gas efficiency
        if (action < Actions.SETTLE) {
            if (action == Actions.SWAP_EXACT_IN) {
                IV4Router.ExactInputParams calldata swapParams = params
                    .decodeSwapExactInParams();
                _swapExactInput(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_IN_SINGLE) {
                IV4Router.ExactInputSingleParams calldata swapParams = params
                    .decodeSwapExactInSingleParams();
                _swapExactInputSingle(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_OUT) {
                IV4Router.ExactOutputParams calldata swapParams = params
                    .decodeSwapExactOutParams();
                _swapExactOutput(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_OUT_SINGLE) {
                IV4Router.ExactOutputSingleParams calldata swapParams = params
                    .decodeSwapExactOutSingleParams();
                _swapExactOutputSingle(swapParams);
                return;
            } else if (action == Actions.INCREASE_LIQUIDITY) {
                (
                    ,
                    uint256 liquidity,
                    uint128 amount0Max,
                    uint128 amount1Max,
                    bytes calldata hookData
                ) = params.decodeModifyLiquidityParams();
                _increase(liquidity, amount0Max, amount1Max, hookData);
                return;
            } else if (action == Actions.INCREASE_LIQUIDITY_FROM_DELTAS) {
                (
                    ,
                    uint128 amount0Max,
                    uint128 amount1Max,
                    bytes calldata hookData
                ) = params.decodeIncreaseLiquidityFromDeltasParams();
                _increaseFromDeltas(amount0Max, amount1Max, hookData);
                return;
            } else if (action == Actions.DECREASE_LIQUIDITY) {
                (
                    ,
                    uint256 liquidity,
                    uint128 amount0Min,
                    uint128 amount1Min,
                    bytes calldata hookData
                ) = params.decodeModifyLiquidityParams();
                _decrease(liquidity, amount0Min, amount1Min, hookData);
                return;
            } else if (action == Actions.MINT_POSITION) {
                (
                    PoolKey calldata poolKey,
                    int24 tickLower,
                    int24 tickUpper,
                    uint256 liquidity,
                    uint128 amount0Max,
                    uint128 amount1Max,
                    ,
                    bytes calldata hookData
                ) = params.decodeMintParams();
                _mint(
                    poolKey,
                    tickLower,
                    tickUpper,
                    liquidity,
                    amount0Max,
                    amount1Max,
                    hookData
                );
                return;
            } else if (action == Actions.MINT_POSITION_FROM_DELTAS) {
                (
                    PoolKey calldata poolKey,
                    int24 tickLower,
                    int24 tickUpper,
                    uint128 amount0Max,
                    uint128 amount1Max,
                    ,
                    bytes calldata hookData
                ) = params.decodeMintFromDeltasParams();
                _mintFromDeltas(
                    poolKey,
                    tickLower,
                    tickUpper,
                    amount0Max,
                    amount1Max,
                    hookData
                );
                return;
            } else if (action == Actions.BURN_POSITION) {
                // Will automatically decrease liquidity to 0 if the position is not already empty.
                (
                    ,
                    uint128 amount0Min,
                    uint128 amount1Min,
                    bytes calldata hookData
                ) = params.decodeBurnParams();
                _burn(amount0Min, amount1Min, hookData);
                return;
            }
        } else {
            if (action == Actions.SETTLE_ALL) {
                (Currency currency, uint256 maxAmount) = params
                    .decodeCurrencyAndUint256();
                uint256 amount = _getFullDebt(currency);
                if (amount > maxAmount)
                    revert V4TooMuchRequested(maxAmount, amount);
                _settle(currency, amount);
                return;
            } else if (action == Actions.TAKE_ALL) {
                (Currency currency, uint256 minAmount) = params
                    .decodeCurrencyAndUint256();
                uint256 amount = _getFullCredit(currency);
                if (amount < minAmount)
                    revert V4TooLittleReceived(minAmount, amount);
                _take(currency, address(this), amount);
                return;
            } else if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount,) = params
                    .decodeCurrencyUint256AndBool();
                _settle(
                    currency,
                    _mapSettleAmount(amount, currency)
                );
                return;
            } else if (action == Actions.TAKE) {
                (Currency currency, , uint256 amount) = params
                    .decodeCurrencyAddressAndUint256();
                _take(
                    currency,
                    address(this),
                    _mapTakeAmount(amount, currency)
                );
                return;
            } else if (action == Actions.TAKE_PORTION) {
                (Currency currency, , uint256 bips) = params
                    .decodeCurrencyAddressAndUint256();
                _take(
                    currency,
                    address(this),
                    _getFullCredit(currency).calculatePortion(bips)
                );
                return;
            }
        }
        revert UnsupportedAction(action);
    }

    /// @dev Calling increase with 0 liquidity will credit the caller with any underlying fees of the position
    function _increase(
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata hookData
    ) internal {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(1);

        // Note: The tokenId is used as the salt for this position, so every minted position has unique storage in the pool manager.
        (
            BalanceDelta liquidityDelta,
            BalanceDelta feesAccrued
        ) = _modifyLiquidity(
                info,
                poolKey,
                liquidity.toInt256(),
                "",
                hookData
            );
        // Slippage checks should be done on the principal liquidityDelta which is the liquidityDelta - feesAccrued
        (liquidityDelta - feesAccrued).validateMaxIn(amount0Max, amount1Max);
    }

    /// @dev The liquidity delta is derived from open deltas in the pool manager.
    function _increaseFromDeltas(
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata hookData
    ) internal {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(1);

        uint256 liquidity;
        {
            (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolKey.toId());

            // Use the credit on the pool manager as the amounts for the mint.
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(info.tickLower()),
                TickMath.getSqrtPriceAtTick(info.tickUpper()),
                _getFullCredit(poolKey.currency0),
                _getFullCredit(poolKey.currency1)
            );
        }

        (
            BalanceDelta liquidityDelta,
            BalanceDelta feesAccrued
        ) = _modifyLiquidity(
                info,
                poolKey,
                liquidity.toInt256(),
                "",
                hookData
            );
        // Slippage checks should be done on the principal liquidityDelta which is the liquidityDelta - feesAccrued
        (liquidityDelta - feesAccrued).validateMaxIn(amount0Max, amount1Max);
    }

    /// @dev Calling decrease with 0 liquidity will credit the caller with any underlying fees of the position
    function _decrease(
        uint256 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        bytes calldata hookData
    ) internal {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(1);

        // Note: the tokenId is used as the salt.
        (
            BalanceDelta liquidityDelta,
            BalanceDelta feesAccrued
        ) = _modifyLiquidity(
                info,
                poolKey,
                -(liquidity.toInt256()),
                "",
                hookData
            );
        // Slippage checks should be done on the principal liquidityDelta which is the liquidityDelta - feesAccrued
        (liquidityDelta - feesAccrued).validateMinOut(amount0Min, amount1Min);
    }

    function _mint(
        PoolKey calldata poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata hookData
    ) internal {
        require(getPositionLiquidity(1) == 0, "Liquidity");

        // Initialize the position info
        PositionInfo info = PositionInfoLibrary.initialize(
            poolKey,
            tickLower,
            tickUpper
        );
        positionInfo[1] = info;

        // Store the poolKey if it is not already stored.
        // On UniswapV4, the minimum tick spacing is 1, which means that if the tick spacing is 0, the pool key has not been set.
        bytes25 poolId = info.poolId();
        if (poolKeys[poolId].tickSpacing == 0) {
            poolKeys[poolId] = poolKey;
        }

        // fee delta can be ignored as this is a new position
        (BalanceDelta liquidityDelta, ) = _modifyLiquidity(
            info,
            poolKey,
            liquidity.toInt256(),
            "",
            hookData
        );
        liquidityDelta.validateMaxIn(amount0Max, amount1Max);
    }

    function _mintFromDeltas(
        PoolKey calldata poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata hookData
    ) internal {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolKey.toId());

        // Use the credit on the pool manager as the amounts for the mint.
        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            _getFullCredit(poolKey.currency0),
            _getFullCredit(poolKey.currency1)
        );

        _mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            hookData
        );
    }

    /// @dev this is overloaded with ERC721Permit_v4._burn
    function _burn(
        uint128 amount0Min,
        uint128 amount1Min,
        bytes calldata hookData
    ) internal {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(1);

        uint256 liquidity = uint256(
            _getLiquidity(1, poolKey, info.tickLower(), info.tickUpper())
        );

        // Can only call modify if there is non zero liquidity.
        BalanceDelta feesAccrued;
        if (liquidity > 0) {
            BalanceDelta liquidityDelta;
            // do not use _modifyLiquidity as we do not need to notify on modification for burns.
            IPoolManager.ModifyLiquidityParams memory params = IPoolManager
                .ModifyLiquidityParams({
                    tickLower: info.tickLower(),
                    tickUpper: info.tickUpper(),
                    liquidityDelta: -(liquidity.toInt256()),
                    salt: ""
                });
            (liquidityDelta, feesAccrued) = poolManager.modifyLiquidity(
                poolKey,
                params,
                hookData
            );
            // Slippage checks should be done on the principal liquidityDelta which is the liquidityDelta - feesAccrued
            (liquidityDelta - feesAccrued).validateMinOut(
                amount0Min,
                amount1Min
            );
        }
    }

    function _swapExactInputSingle(
        IV4Router.ExactInputSingleParams calldata params
    ) private {
        uint128 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn = _getFullCredit(
                params.zeroForOne
                    ? params.poolKey.currency0
                    : params.poolKey.currency1
            ).toUint128();
        }
        uint128 amountOut = _swap(
            params.poolKey,
            params.zeroForOne,
            -int256(uint256(amountIn)),
            params.hookData
        ).toUint128();
        if (amountOut < params.amountOutMinimum)
            revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
    }

    function _swapExactInput(
        IV4Router.ExactInputParams calldata params
    ) private {
        unchecked {
            // Caching for gas savings
            uint256 pathLength = params.path.length;
            uint128 amountOut;
            Currency currencyIn = params.currencyIn;
            uint128 amountIn = params.amountIn;
            if (amountIn == ActionConstants.OPEN_DELTA)
                amountIn = _getFullCredit(currencyIn).toUint128();
            PathKey calldata pathKey;

            for (uint256 i = 0; i < pathLength; i++) {
                pathKey = params.path[i];
                (PoolKey memory poolKey, bool zeroForOne) = pathKey
                    .getPoolAndSwapDirection(currencyIn);
                // The output delta will always be positive, except for when interacting with certain hook pools
                amountOut = _swap(
                    poolKey,
                    zeroForOne,
                    -int256(uint256(amountIn)),
                    pathKey.hookData
                ).toUint128();

                amountIn = amountOut;
                currencyIn = pathKey.intermediateCurrency;
            }

            if (amountOut < params.amountOutMinimum)
                revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
        }
    }

    function _swapExactOutputSingle(
        IV4Router.ExactOutputSingleParams calldata params
    ) private {
        uint128 amountOut = params.amountOut;
        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut = _getFullDebt(
                params.zeroForOne
                    ? params.poolKey.currency1
                    : params.poolKey.currency0
            ).toUint128();
        }
        uint128 amountIn = (
            uint256(
                -int256(
                    _swap(
                        params.poolKey,
                        params.zeroForOne,
                        int256(uint256(amountOut)),
                        params.hookData
                    )
                )
            )
        ).toUint128();
        if (amountIn > params.amountInMaximum)
            revert V4TooMuchRequested(params.amountInMaximum, amountIn);
    }

    function _swapExactOutput(
        IV4Router.ExactOutputParams calldata params
    ) private {
        unchecked {
            // Caching for gas savings
            uint256 pathLength = params.path.length;
            uint128 amountIn;
            uint128 amountOut = params.amountOut;
            Currency currencyOut = params.currencyOut;
            PathKey calldata pathKey;

            if (amountOut == ActionConstants.OPEN_DELTA) {
                amountOut = _getFullDebt(currencyOut).toUint128();
            }

            for (uint256 i = pathLength; i > 0; i--) {
                pathKey = params.path[i - 1];
                (PoolKey memory poolKey, bool oneForZero) = pathKey
                    .getPoolAndSwapDirection(currencyOut);
                // The output delta will always be negative, except for when interacting with certain hook pools
                amountIn = (
                    uint256(
                        -int256(
                            _swap(
                                poolKey,
                                !oneForZero,
                                int256(uint256(amountOut)),
                                pathKey.hookData
                            )
                        )
                    )
                ).toUint128();

                amountOut = amountIn;
                currencyOut = pathKey.intermediateCurrency;
            }
            if (amountIn > params.amountInMaximum)
                revert V4TooMuchRequested(params.amountInMaximum, amountIn);
        }
    }

    function _swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata hookData
    ) private returns (int128 reciprocalAmount) {
        // for protection of exactOut swaps, sqrtPriceLimit is not exposed as a feature in this contract
        unchecked {
            BalanceDelta delta = poolManager.swap(
                poolKey,
                IPoolManager.SwapParams(
                    zeroForOne,
                    amountSpecified,
                    zeroForOne
                        ? TickMath.MIN_SQRT_PRICE + 1
                        : TickMath.MAX_SQRT_PRICE - 1
                ),
                hookData
            );

            reciprocalAmount = (zeroForOne == amountSpecified < 0)
                ? delta.amount1()
                : delta.amount0();
        }
    }

        function _modifyLiquidity(
        PositionInfo info,
        PoolKey memory poolKey,
        int256 liquidityChange,
        bytes32 salt,
        bytes calldata hookData
    ) internal returns (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) {
        (liquidityDelta, feesAccrued) = poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: info.tickLower(),
                tickUpper: info.tickUpper(),
                liquidityDelta: liquidityChange,
                salt: salt
            }),
            hookData
        );

    }

        function getPoolAndPositionInfo(uint256 tokenId) public view returns (PoolKey memory poolKey, PositionInfo info) {
        info = positionInfo[tokenId];
        poolKey = poolKeys[info.poolId()];
    }
        function getPositionLiquidity(uint256 tokenId) public view returns (uint128 liquidity) {
        (PoolKey memory poolKey, PositionInfo info) = getPoolAndPositionInfo(tokenId);
        liquidity = _getLiquidity(tokenId, poolKey, info.tickLower(), info.tickUpper());
    }
        function _getLiquidity(uint256 tokenId, PoolKey memory poolKey, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint128 liquidity)
    {
        bytes32 positionId = Position.calculatePositionKey(address(this), tickLower, tickUpper, bytes32(tokenId));
        liquidity = poolManager.getPositionLiquidity(poolKey.toId(), positionId);
    }
}
