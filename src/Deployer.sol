// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AutomatizationHook} from "./AutomatizationHook.sol";


/// @notice Mines the address and deploys the Rebalance.sol Hook contract
contract RebalanceHookScript {

        function deploy(bytes32 salt) public {
        // hook contracts must have specific flags encoded in the address

        new AutomatizationHook{salt: salt}(msg.sender);
    }
}