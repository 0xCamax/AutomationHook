// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "./Rebalance.sol";

contract Manager is Rebalance {
    constructor(
        address tokenA,
        address tokenB,
        address hook
    ) Rebalance(tokenA, tokenB, hook) {}

    function setPoolKey(
        address tokenA,
        address tokenB,
        int24 tickSpacing,
        uint24 fee,
        address hook
    ) external onlyOwner {
        (address currency0, address currency1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        poolKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            tickSpacing: tickSpacing,
            fee: fee,
            hooks: IHooks(hook)
        });

        swapPool = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            tickSpacing: 10,
            fee: 500,
            hooks: IHooks(address(0))
        });

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

    function setFee(uint24 fee) external onlyOwner {
        poolKey.fee = fee;
    }

    function setTickSpacing(int24 tickSpacing) external onlyOwner {
        poolKey.tickSpacing = tickSpacing;
    }

    function setSlippageTolerance(int24 tolerance) public onlyOwner {
        slippageTolerance = tolerance;
    }

    function withdraw() public onlyOwner {
        (int256 balance0, int256 balance1) = balances();
        poolKey.currency0.transfer(owner, uint256(balance0));
        poolKey.currency1.transfer(owner, uint256(balance1));
    }

    function setWidth(int24 lw, int24 uw) public onlyOwner {
        lowerWidth = lw;
        upperWidth = uw;
    }
}
