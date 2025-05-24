// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook/src/structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchProjectConfig} from "@bananapus/721-hook/src/structs/JBLaunchProjectConfig.sol";
import {JBQueueRulesetsConfig} from "@bananapus/721-hook/src/structs/JBQueueRulesetsConfig.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core/src/structs/REVSuckerDeploymentConfig.sol";

import {JBDeployerHookConfig} from "../structs/JBDeployerHookConfig.sol";

interface IJBOmnichainDeployer {
    function dataHookOf(
        uint256 projectId,
        uint256 rulesetId
    )
        external
        view
        returns (bool useDataHookForPay, bool useDataHookForCashout, IJBRulesetDataHook dataHook);

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

    function launch721ProjectFor(
        address owner,
        JBDeploy721TiersHookConfig calldata deployTiersHookConfig,
        JBLaunchProjectConfig calldata launchProjectConfig,
        bytes32 salt,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        returns (uint256 projectId, IJB721TiersHook hook, address[] memory suckers);

    function launchRulesetsFor(
        uint256 projectId,
        JBRulesetConfig[] calldata rulesetConfigurations,
        JBTerminalConfig[] memory terminalConfigurations,
        string calldata memo
    )
        external
        returns (uint256 rulesetId);

    function queueRulesetsOf(
        uint256 projectId,
        JBRulesetConfig[] calldata rulesetConfigurations,
        string calldata memo
    )
        external
        returns (uint256 rulesetId);

    function queue721RulesetsOf(
        uint256 projectId,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBQueueRulesetsConfig memory queueRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 rulesetId, IJB721TiersHook hook);
}
