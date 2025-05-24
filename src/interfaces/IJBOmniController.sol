// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core/src/structs/REVSuckerDeploymentConfig.sol";

/// @title IJBOmniController
/// @notice Interface for the JBOmniController contract that handles omnichain project deployment and management.
interface IJBOmniController is IJBController {
    event DeployERC20(uint256 indexed projectId, string name, string symbol, bytes32 salt, address caller);

    function launchProjectFor(
        address owner,
        string calldata projectUri,
        JBRulesetConfig[] calldata rulesetConfigurations,
        JBTerminalConfig[] calldata terminalConfigurations,
        string calldata memo,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        returns (uint256 projectId, address[] memory suckers);
}
