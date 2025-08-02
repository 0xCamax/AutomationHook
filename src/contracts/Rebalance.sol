// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {IPoolManager, IHooks, Currency} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {LiquidityMax} from "../libraries/LiquidityMax.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {TransientStateLibrary} from "../libraries/TransientStateLibrary.sol";
import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IV3Factory} from "../interfaces/IV3Factory.sol";
import {IV3Pool} from "../interfaces/IV3Pool.sol";
import {TickGuard} from "../libraries/TickGuard.sol";
import {ImmutableState} from "../contracts/ImmutableState.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import {Ownable} from "./Ownable.sol";

struct Position {
    int24 initialPrice;
    int24 tickLower;
    int24 tickUpper;
    int128 liquidity;
}

enum Actions {
    EXIT,
    REBALANCE,
    ADDLIQUIDITY
}

abstract contract Rebalance is ImmutableState, Ownable {
    using TransientStateLibrary for IPoolManager;

    Position public state;
    PoolKey public poolKey;
    PoolKey public swapPool;
    int24 slippageTolerance;
    int24 lowerWidth;
    int24 upperWidth;

    IV3Pool oracle;

    constructor(
        address tokenA,
        address tokenB,
        address hook
    ) Ownable(msg.sender) {
        (address currency0, address currency1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            tickSpacing: 1,
            fee: 500,
            hooks: IHooks(hook)
        });

        slippageTolerance = 50; //1%

        swapPool = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            tickSpacing: 10,
            fee: 500,
            hooks: IHooks(address(0))
        });

        lowerWidth = 2;
        upperWidth = 2;

        oracle = IV3Pool(
            IV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984).getPool(
                CurrencyLibrary.isAddressZero(poolKey.currency0)
                    ? 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
                    : Currency.unwrap(poolKey.currency0),
                CurrencyLibrary.isAddressZero(poolKey.currency1)
                    ? 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
                    : Currency.unwrap(poolKey.currency1),
                500
            )
        );
    }

    function initialize() public onlyOwner {
        uint160 price = TickMath.getSqrtPriceAtTick(meanTick());
        poolManager.initialize(poolKey, price);
    }

    function getPriceInfo()
        public
        view
        returns (uint160 price, int24 currentTick)
    {
        (price, currentTick, , ) = stateView.getSlot0(poolKey.toId());
    }

    function outOfRange() public view returns (bool) {
        (, int24 tick) = getPriceInfo();
        return
            tick <= state.tickLower + (lowerWidth / 2) ||
            tick >= state.tickUpper - (upperWidth / 2);
    }

    function slippageCheck(int24 tick) internal view returns (bool) {
        int24 _meanTick = meanTick();
        return TickGuard._isTickWithinRange(tick, _meanTick, slippageTolerance);
    }

    function meanTick() public view returns (int24) {
        if (oracle.token1() == Currency.unwrap(poolKey.currency1)) {
            return TickGuard.meanTick(5, oracle);
        } else {
            return -TickGuard.meanTick(5, oracle);
        }
    }

    function execute(Actions action) external {
        poolManager.unlock(abi.encode(action));
    }

    function removeLiquidity(int128 amount) internal {
        require(
            amount < 0 && amount >= -int256(state.liquidity),
            "RL: Invalid Amount"
        );
        poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams(
                state.tickLower,
                state.tickUpper,
                amount,
                ""
            ),
            ""
        );
        state.liquidity += amount;
    }

    function addLiquidity(
        int128 amount,
        int24 tick,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        require(amount > 0, "AL: Invalid Amount");
        poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams(
                tickLower,
                tickUpper,
                amount,
                ""
            ),
            ""
        );
        state = Position(tick, tickLower, tickUpper, state.liquidity + amount);
    }

    function swap(bool zeroForOne, int256 amount) internal {
        poolManager.swap(
            swapPool,
            IPoolManager.SwapParams(
                zeroForOne,
                amount,
                zeroForOne
                    ? TickMath.getSqrtPriceAtTick(
                        meanTick() - slippageTolerance
                    )
                    : TickMath.getSqrtPriceAtTick(
                        meanTick() + slippageTolerance
                    )
            ),
            ""
        );
    }

    function settle(int256 amount) internal {
        if (uint256(-amount) <= poolKey.currency0.balanceOfSelf()) {
            if (poolKey.currency0.isAddressZero()) {
                poolManager.settle{value: uint256(-amount)}();
            } else {
                poolManager.sync(poolKey.currency0);
                poolKey.currency0.transfer(
                    address(poolManager),
                    uint256(-amount)
                );
                poolManager.settle();
            }
        } else {
            removeLiquidity(-(state.liquidity / 1000));
            resolve();
        }
    }

    function resolve() internal returns (int256 amount0, int256 amount1) {
        amount1 = poolManager.currencyDelta(address(this), poolKey.currency1);
        if (amount1 < 0) {
            swap(true, int256(-amount1));
        } else if (amount1 > 0) {
            swap(false, -amount1);
        }

        amount0 = poolManager.currencyDelta(address(this), poolKey.currency0);

        if (amount0 > 0) {
            take(amount0);
        } else {
            settle(amount0);
        }
    }

    function getPositionParams(uint256 balance0, uint256 balance1)
        public
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        (uint160 price, int24 tick) = getPriceInfo();
        require(slippageCheck(tick), "TickGuard: Out of range");
        int24 baseTick = tick - (tick % poolKey.tickSpacing);

        tickLower = baseTick - (lowerWidth * poolKey.tickSpacing);
        tickUpper = baseTick + (upperWidth * poolKey.tickSpacing);

        (, , liquidity) = LiquidityMax.getMaxLiquidityAmounts(
            price,
            tickLower,
            tickUpper,
            balance0,
            balance1
        );
    }

    function balances()
        internal
        view
        returns (int256 balance0, int256 balance1)
    {
        (uint160 currentPrice, ) = getPriceInfo();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                currentPrice,
                TickMath.getSqrtPriceAtTick(state.tickLower),
                TickMath.getSqrtPriceAtTick(state.tickUpper),
                uint128(state.liquidity)
            );
        return (
            int256(poolKey.currency0.balanceOfSelf()) + int256(amount0),
            int256(poolKey.currency1.balanceOfSelf()) + int256(amount1)
        );
    }

    function main(Actions action) internal returns (bytes memory) {
        (int256 balance0, int256 balance1) = balances();
        if (action == Actions.EXIT) {
            removeLiquidity(-int128(state.liquidity));
            resolve();
        }
        if (action == Actions.ADDLIQUIDITY) {
            (
                int24 tickLower,
                int24 tickUpper,
                uint128 liquidity
            ) = getPositionParams(uint256(balance0), uint256(balance1));
            (, int24 tick) = getPriceInfo();
            addLiquidity(int128(liquidity), tick, tickLower, tickUpper);
            resolve();
        }
        if (action == Actions.REBALANCE){
            rebalance();
        }

        require(poolManager.getNonzeroDeltaCount() == 0, "Deltas: Unresolved");
        return abi.encode(true);
    }

    function take(int256 amount) internal {
        poolManager.take(poolKey.currency0, address(this), uint256(amount));
    }

    function rebalance() public {
        (int256 balance0, int256 balance1) = balances();
        removeLiquidity(-int128(state.liquidity));
        (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        ) = getPositionParams(uint256(balance0), uint256(balance1));
        (, int24 tick) = getPriceInfo();
        addLiquidity(int128(liquidity), tick, tickLower, tickUpper);
        resolve();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        Actions action = abi.decode(data, (Actions));
        return main(action);
    }

    receive() external payable {}
}
