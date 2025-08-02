// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILimitOrder {
    struct ClaimProtocolFeesParams {
        address pool;
        int24 tickLower;
        int24 tickUpper;
        uint128 fees0;
        uint128 fees1;
    }

    struct ClosePositionsParams {
        address user;
        uint256 index;
    }

    struct OrderParams {
        address pool;
        int24 target;
        bool zeroForOne;
        uint256 tokenAmount;
    }

    struct PositionInfo {
        address pool;
        address owner;
        uint128 liquidity;
        bool zeroForOne;
        int24 tickLower;
        int24 tickUpper;
    }
    function getUserPositions(
        address user
    ) external view returns (PositionInfo[] memory);

    function limitOrder(OrderParams memory params) external;

    function adjustPosition(uint256 index, int24 target) external;

    function cancelPosition(
        uint256 index
    ) external returns (uint256 amount0, uint256 amount1);

    function closePosition(bytes[] memory params) external;

    function claimProtocolFees(bytes[] memory params) external;

    function computeClosePositionsParams()
        external
        view
        returns (bytes[] memory data);

    function computeClaimProtocolFeesParams()
        external
        view
        returns (bytes[] memory data);

    function checkPosition(
        PositionInfo memory position
    ) external view returns (bool);

    function userPositions(address user, uint256 index) external view returns (PositionInfo memory);
}
