// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {TickMath} from "./TickMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";

library LiquidityMax {
    function getMaxLiquidityAmounts(
        uint160 currentPrice,
        int24 tickLower,
        int24 tickUpper,
        uint256 balance0,
        uint256 balance1
    )
        internal
        pure
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidity
        )
    {
        uint160 priceA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 priceB = TickMath.getSqrtPriceAtTick(tickUpper);

        uint256 balance = totalBalance(balance0, balance1, currentPrice);

        (amount0, balance1) = getDistribution(
            currentPrice,
            priceA,
            priceB,
            balance
        );

        amount1 = toToken1(balance1, currentPrice);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            currentPrice,
            priceA,
            priceB,
            amount0,
            amount1
        );
    }

    function getDistribution(
        uint160 currentSqrtPrice,
        uint160 tickLowerPrice,
        uint160 tickUpperPrice,
        uint256 totalTokenBalance
    ) internal pure returns (uint256 tokenAmount0, uint256 tokenAmount1) {
        uint256 PRECISION_SCALE = 1e18;
        if (currentSqrtPrice < tickLowerPrice) {
            tokenAmount0 = totalTokenBalance;
            tokenAmount1 = 0;
            return (tokenAmount0, tokenAmount1);
        }

        if (currentSqrtPrice > tickUpperPrice) {
            tokenAmount0 = 0;
            tokenAmount1 = totalTokenBalance;
            return (tokenAmount0, tokenAmount1);
        }

        if (
            currentSqrtPrice >= tickLowerPrice &&
            currentSqrtPrice < tickUpperPrice
        ) {
            uint256 priceDeltaFromLower = currentSqrtPrice - tickLowerPrice;
            uint256 priceDeltaFromUpper = tickUpperPrice - currentSqrtPrice;

            uint256 ratioFromLower = (priceDeltaFromLower * PRECISION_SCALE) /
                (priceDeltaFromLower + priceDeltaFromUpper);
            uint256 ratioFromUpper = (priceDeltaFromUpper * PRECISION_SCALE) /
                (priceDeltaFromLower + priceDeltaFromUpper);

            tokenAmount0 =
                (totalTokenBalance * ratioFromUpper) /
                PRECISION_SCALE;
            tokenAmount1 = totalTokenBalance - tokenAmount0;

            if (tokenAmount0 < tokenAmount1) {
                tokenAmount1 =
                    (totalTokenBalance * ratioFromLower) /
                    PRECISION_SCALE;
                tokenAmount0 = totalTokenBalance - tokenAmount1;
                return (tokenAmount0, tokenAmount1);
            }
        }
    }

    function totalBalance(
        uint256 balance0,
        uint256 balance1,
        uint160 currentPrice
    ) internal pure returns (uint256) {
        return balance0 + toToken0(balance1, currentPrice);
    }

    function getPrice(uint160 sqrtPriceX96)
        internal
        pure
        returns (uint256 price)
    {
        uint256 scale = 10**uint256(estimateMaxScale(sqrtPriceX96));

        assembly {
            let priceX96 := mul(mul(sqrtPriceX96, sqrtPriceX96), scale)
            price := shr(192, priceX96)
        }
    }

    function toToken0(uint256 balance1, uint160 currentPrice)
        internal
        pure
        returns (uint256)
    {
        uint256 price = getPrice(currentPrice);
        uint256 scale = 10**(uint256(estimateMaxScale(currentPrice)));
        return ((balance1 * scale) / price);
    }

    function toToken1(uint256 balance0, uint160 currentPrice)
        internal
        pure
        returns (uint256)
    {
        uint256 price = getPrice(currentPrice);
        uint256 scale = 10**(uint256(estimateMaxScale(currentPrice)));
        return ((balance0 * price) / scale);
    }

    function estimateMaxScale(uint256 sqrtPriceX96)
        private
        pure
        returns (int256)
    {
        // Coeficientes ajustados con regresión logarítmica basada en tus datos
        int256 A = 7074990468513481;
        int256 B = 187159504898758;

        // Cálculo de logaritmo usando aproximación
        int256 logValue = int256((log2(sqrtPriceX96) * 1e18) / log2(10));

        // Estimación de la escala
        int256 maxScale = A - ((B * logValue) / 1e18);

        // Limitar valores negativos
        return maxScale > 0 ? int256(maxScale) / 1e14 : int256(0);
    }

    function log2(uint256 x) private pure returns (uint256 y) {
        assembly {
            let arg := x
            let r := 0
            if gt(arg, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                arg := shr(128, arg)
                r := add(r, 128)
            }
            if gt(arg, 0xFFFFFFFFFFFFFFFF) {
                arg := shr(64, arg)
                r := add(r, 64)
            }
            if gt(arg, 0xFFFFFFFF) {
                arg := shr(32, arg)
                r := add(r, 32)
            }
            if gt(arg, 0xFFFF) {
                arg := shr(16, arg)
                r := add(r, 16)
            }
            if gt(arg, 0xFF) {
                arg := shr(8, arg)
                r := add(r, 8)
            }
            if gt(arg, 0xF) {
                arg := shr(4, arg)
                r := add(r, 4)
            }
            if gt(arg, 0x3) {
                arg := shr(2, arg)
                r := add(r, 2)
            }
            if gt(arg, 0x1) {
                r := add(r, 1)
            }
            y := r
        }
    }
}
