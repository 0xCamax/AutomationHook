// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IImmutableState} from "../interfaces/IImmutableState.sol";
import {IStateView} from "../interfaces/IStateView.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";

/// @title Immutable State
/// @notice A collection of immutable state variables, commonly used across multiple contracts
contract ImmutableState is IImmutableState {
    /// @inheritdoc IImmutableState
    IPoolManager public constant poolManager = IPoolManager(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
    IStateView public constant stateView = IStateView(0x76Fd297e2D437cd7f76d50F01AfE6160f86e9990);
    IPositionManager public constant posm = IPositionManager(0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869);

}
