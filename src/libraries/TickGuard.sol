// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {IV3Pool} from "../interfaces/IV3Pool.sol";

library TickGuard {


    function meanTick(uint32 secondsAgo, IV3Pool pool) internal view returns (int24) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        return int24(tickCumulativesDelta / int32(secondsAgo));
    }

    function _isTickWithinRange(int24 tick, int24 _meanTick, int24 tolerance) internal pure returns (bool) {
        int24 lowerLimit = _meanTick - tolerance;
        int24 upperLimit = _meanTick + tolerance;
        return tick >= lowerLimit && tick <= upperLimit;
    }
}
