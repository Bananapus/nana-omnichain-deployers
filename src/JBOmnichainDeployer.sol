// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookProjectDeployer.sol";
import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook/src/structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchProjectConfig} from "@bananapus/721-hook/src/structs/JBLaunchProjectConfig.sol";
import {JBLaunchRulesetsConfig} from "@bananapus/721-hook/src/structs/JBLaunchRulesetsConfig.sol";
import {JBPayDataHookRulesetConfig} from "@bananapus/721-hook/src/structs/JBPayDataHookRulesetConfig.sol";
import {JBQueueRulesetsConfig} from "@bananapus/721-hook/src/structs/JBQueueRulesetsConfig.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {JBBeforeCashOutRecordedContext} from "@bananapus/core/src/structs/JBBeforeCashOutRecordedContext.sol";

import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {JBCashOutHookSpecification} from "@bananapus/core/src/structs/JBCashOutHookSpecification.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";

import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
import {JBPayDataHookRulesetMetadata} from "@bananapus/721-hook/src/structs/JBPayDataHookRulesetMetadata.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core/src/structs/JBRulesetMetadata.sol";
import {JBRuleset} from "@bananapus/core/src/structs/JBRuleset.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {REVSuckerDeploymentConfig} from "@rev-net/core/src/structs/REVSuckerDeploymentConfig.sol";

import {IJBOmnichainDeployer} from "./interfaces/IJBOmnichainDeployer.sol";
import {JBDeployerHookConfig} from "./structs/JBDeployerHookConfig.sol";
import {JBOwnable} from "@bananapus/ownable/src/JBOwnable.sol";

/// @notice Deploys, manages, and operates Juicebox projects with suckers.
contract JBOmnichainDeployer is
    ERC2771Context,
    JBPermissioned,
    IJBOmnichainDeployer,
    IJBRulesetDataHook,
    IERC721Receiver
{
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The controller used to create and manage Juicebox projects.
    IJBController public immutable CONTROLLER;

    /// @notice Mints ERC-721s that represent Juicebox project ownership and transfers.
    IJBProjects public immutable PROJECTS;

    /// @notice Deploys tiered ERC-721 hooks for projects.
    IJB721TiersHookDeployer public immutable HOOK_DEPLOYER;

    /// @notice Deploys and tracks suckers for projects.
    IJBSuckerRegistry public immutable SUCKER_REGISTRY;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice Each project's data hook provided on deployment.
    /// @custom:param projectId The ID of the project to get the data hook for.
    /// @custom:param rulesetId The ID of the ruleset to get the data hook for.
    mapping(uint256 projectId => mapping(uint256 rulesetId => JBDeployerHookConfig)) public override dataHookOf;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller to use for launching and operating the Juicebox projects.
    /// @param suckerRegistry The registry to use for deploying and tracking each project's suckers.
    /// @param hookDeployer The deployer to use for project's tiered ERC-721 hooks.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBController controller,
        IJBSuckerRegistry suckerRegistry,
        IJB721TiersHookDeployer hookDeployer,
        address trustedForwarder
    )
        JBPermissioned(IJBPermissioned(address(controller)).PERMISSIONS())
        ERC2771Context(trustedForwarder)
    {
        CONTROLLER = controller;
        PROJECTS = controller.PROJECTS();
        SUCKER_REGISTRY = suckerRegistry;
        HOOK_DEPLOYER = hookDeployer;

        // Give the sucker registry permission to map tokens for all revnets.
        uint8[] memory permissionIds = new uint8[](1);
        permissionIds[0] = JBPermissionIds.MAP_SUCKER_TOKEN;

        // Give the operator the permission.
        // Set up the permission data.
        JBPermissionsData memory permissionData =
            JBPermissionsData({operator: address(SUCKER_REGISTRY), projectId: 0, permissionIds: permissionIds});

        // Set the permissions.
        PERMISSIONS.setPermissionsFor({account: address(this), permissionsData: permissionData});
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Forward the call to the original data hook.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a payment.
    /// @param context Standard Juicebox payment context. See `JBBeforePayRecordedContext`.
    /// @return weight The weight which project tokens are minted relative to. This can be used to customize how many
    /// tokens get minted by a payment.
    /// @return hookSpecifications Amounts (out of what's being paid in) to be sent to pay hooks instead of being paid
    /// into the project. Useful for automatically routing funds from a treasury as payments come in.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Fetch the datahook for the ruleset.
        JBDeployerHookConfig memory hook = dataHookOf[context.projectId][context.rulesetId];

        // If no data hook is set, return the original values.
        if (address(hook.dataHook) == address(0) || !hook.useDataHookForPay) {
            return (context.weight, hookSpecifications);
        }

        // Otherwise, forward the call to the datahook.
        return hook.dataHook.beforePayRecordedWith(context);
    }

    /// @notice Allow cash outs from suckers without a tax.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a cash out.
    /// @param context Standard Juicebox cash out context. See `JBBeforeCashOutRecordedContext`.
    /// @return cashOutTaxRate The cash out tax rate, which influences the amount of terminal tokens which get cashed
    /// out.
    /// @return cashOutCount The number of project tokens that are cashed out.
    /// @return totalSupply The total project token supply.
    /// @return hookSpecifications The amount of funds and the data to send to cash out hooks (this contract).
    function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
        external
        view
        override
        returns (
            uint256 cashOutTaxRate,
            uint256 cashOutCount,
            uint256 totalSupply,
            JBCashOutHookSpecification[] memory hookSpecifications
        )
    {
        // If the cash out is from a sucker, return the full cash out amount without taxes or fees.
        if (SUCKER_REGISTRY.isSuckerOf(context.projectId, context.holder)) {
            return (0, context.cashOutCount, context.totalSupply, hookSpecifications);
        }

        // Fetch the datahook for the ruleset.
        JBDeployerHookConfig memory hook = dataHookOf[context.projectId][context.rulesetId];

        // If no data hook is set, or the data hook is not used for cash outs, return the original values.
        if (address(hook.dataHook) == address(0) || !hook.useDataHookForCashOut) {
            return (context.cashOutTaxRate, context.cashOutCount, context.totalSupply, hookSpecifications);
        }

        // If the ruleset has a data hook, forward the call to the datahook.
        return hook.dataHook.beforeCashOutRecordedWith(context);
    }

    /// @notice A flag indicating whether an address has permission to mint a project's tokens on-demand.
    /// @dev A project's data hook can allow any address to mint its tokens.
    /// @param projectId The ID of the project whose token can be minted.
    /// @param addr The address to check the token minting permission of.
    /// @return flag A flag indicating whether the address has permission to mint the project's tokens on-demand.
    function hasMintPermissionFor(uint256 projectId, address addr) external view returns (bool flag) {
        // If the address is a sucker for this project.
        if (SUCKER_REGISTRY.isSuckerOf(projectId, addr)) {
            return true;
        }

        // Get the current ruleset of the project.
        (JBRuleset memory ruleset,) = CONTROLLER.currentRulesetOf(projectId);
        JBDeployerHookConfig memory hook = dataHookOf[projectId][ruleset.id];

        // If no data hook is set, return false.
        if (address(hook.dataHook) == address(0)) {
            return false;
        }

        // Forward the call to the datahook.
        return hook.dataHook.hasMintPermissionFor(projectId, addr);
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See `IERC165.supportsInterface`.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IJBOmnichainDeployer).interfaceId
            || interfaceId == type(IJBRulesetDataHook).interfaceId || interfaceId == type(IERC721Receiver).interfaceId;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Deploy new suckers for an existing project.
    /// @dev Only the juicebox's owner can deploy new suckers.
    /// @param projectId The ID of the project to deploy suckers for.
    /// @param suckerDeploymentConfiguration The suckers to set up for the project.
    function deploySuckersFor(
        uint256 projectId,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        returns (address[] memory suckers)
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.DEPLOY_SUCKERS
        });

        // Deploy the suckers.
        // slither-disable-next-line unused-return
        suckers = SUCKER_REGISTRY.deploySuckersFor({
            projectId: projectId,
            salt: keccak256(abi.encode(suckerDeploymentConfiguration.salt, _msgSender())),
            configurations: suckerDeploymentConfiguration.deployerConfigurations
        });
    }

    /// @notice Creates a project with suckers.
    /// @dev This will mint the project's ERC-721 to the `owner`'s address, queue the specified rulesets, and set up the
    /// specified splits and terminals. Each operation within this transaction can be done in sequence separately.
    /// @dev Anyone can deploy a project to any `owner`'s address.
    /// @param owner The project's owner. The project ERC-721 will be minted to this address.
    /// @param projectUri The project's metadata URI. This is typically an IPFS hash, optionally with the `ipfs://`
    /// prefix. This can be updated by the project's owner.
    /// @param rulesetConfigurations The rulesets to queue.
    /// @param terminalConfigurations The terminals to set up for the project.
    /// @param memo A memo to pass along to the emitted event.
    /// @param suckerDeploymentConfiguration The suckers to set up for the project. Suckers facilitate cross-chain
    /// token transfers between peer projects on different networks.
    /// @return projectId The project's ID.
    function launchProjectFor(
        address owner,
        string calldata projectUri,
        JBRulesetConfig[] memory rulesetConfigurations,
        JBTerminalConfig[] calldata terminalConfigurations,
        string calldata memo,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        returns (uint256 projectId, address[] memory suckers)
    {
        // Get the next project ID.
        projectId = PROJECTS.count() + 1;

        rulesetConfigurations = _setup({projectId: projectId, rulesetConfigurations: rulesetConfigurations});

        // Launch the project.
        assert(
            projectId
                == CONTROLLER.launchProjectFor({
                    owner: address(this),
                    projectUri: projectUri,
                    rulesetConfigurations: rulesetConfigurations,
                    terminalConfigurations: terminalConfigurations,
                    memo: memo
                })
        );

        // Deploy the suckers (if applicable).
        if (suckerDeploymentConfiguration.salt != bytes32(0)) {
            // Deploy the suckers.
            // slither-disable-next-line unused-return
            suckers = SUCKER_REGISTRY.deploySuckersFor({
                projectId: projectId,
                salt: keccak256(abi.encode(suckerDeploymentConfiguration.salt, _msgSender())),
                configurations: suckerDeploymentConfiguration.deployerConfigurations
            });
        }

        // Transfer ownership of the project to the owner.
        PROJECTS.transferFrom(address(this), owner, projectId);
    }

    /// @notice Launches a new project with a 721 tiers hook attached, and with suckers.
    /// @param owner The address to set as the owner of the project. The ERC-721 which confers this project's ownership
    /// will be sent to this address.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook which is being
    /// deployed.
    /// @param launchProjectConfig Configuration which dictates the behavior of the project which is being launched.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return projectId The ID of the newly launched project.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function launch721ProjectFor(
        address owner,
        JBDeploy721TiersHookConfig calldata deployTiersHookConfig,
        JBLaunchProjectConfig calldata launchProjectConfig,
        bytes32 salt,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        returns (uint256 projectId, IJB721TiersHook hook, address[] memory suckers)
    {
        // Get the next project ID.
        projectId = PROJECTS.count() + 1;

        // Deploy the hook.
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: projectId,
            deployTiersHookConfig: deployTiersHookConfig,
            salt: salt == bytes32(0) ? bytes32(0) : keccak256(abi.encode(_msgSender(), salt))
        });

        // Convert the 721 ruleset configurations to regular ruleset configurations.
        // Then modify the ruleset configurations to use this deployer as a wrapper for the datasouce.
        JBRulesetConfig[] memory rulesetConfigurations = _setup({
            projectId: projectId,
            rulesetConfigurations: _from721Config(launchRulesetsConfig.rulesetConfigurations, hook)
        });

        // Launch the project, and sanity check the project ID.
        assert(
            projectId
                == CONTROLLER.launchProjectFor({
                    owner: address(this),
                    projectUri: launchProjectConfig.projectUri,
                    rulesetConfigurations: rulesetConfigurations,
                    terminalConfigurations: launchProjectConfig.terminalConfigurations,
                    memo: launchProjectConfig.memo
                })
        );

        // Transfer the hook's ownership to the project.
        JBOwnable(address(hook)).transferOwnershipToProject(projectId);

        // Deploy the suckers (if applicable).
        if (suckerDeploymentConfiguration.salt != bytes32(0)) {
            // Deploy the suckers.
            // slither-disable-next-line unused-return
            suckers = SUCKER_REGISTRY.deploySuckersFor({
                projectId: projectId,
                salt: keccak256(abi.encode(suckerDeploymentConfiguration.salt, _msgSender())),
                configurations: suckerDeploymentConfiguration.deployerConfigurations
            });
        }

        // Transfer ownership of the project to the owner.
        PROJECTS.transferFrom(address(this), owner, projectId);
    }

    /// @notice Launches new rulesets for a project, using this contract as the data hook.
    /// @param projectId The ID of the project to launch the rulesets for.
    /// @param rulesetConfigurations The rulesets to launch.
    /// @param terminalConfigurations The terminals to set up for the project.
    /// @param memo A memo to pass along to the emitted event.
    /// @return rulesetId The ID of the newly launched rulesets.
    function launchRulesetsFor(
        uint256 projectId,
        JBRulesetConfig[] calldata rulesetConfigurations,
        JBTerminalConfig[] calldata terminalConfigurations,
        string calldata memo
    )
        external
        returns (uint256)
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.QUEUE_RULESETS
        });

        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.SET_TERMINALS
        });

        return CONTROLLER.launchRulesetsFor({
            projectId: projectId,
            rulesetConfigurations: _setup({projectId: projectId, rulesetConfigurations: rulesetConfigurations}),
            terminalConfigurations: terminalConfigurations,
            memo: memo
        });
    }

    /// @notice Launches new rulesets for a project with a 721 tiers hook attached, using this contract as the data
    /// hook.
    /// @param projectId The ID of the project to launch the rulesets for.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook which is being
    /// deployed.
    /// @param launchRulesetsConfig Configuration which dictates the behavior of the rulesets which are being launched.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return rulesetId The ID of the newly launched rulesets.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function launch721RulesetsFor(
        uint256 projectId,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBLaunchRulesetsConfig calldata launchRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 rulesetId, IJB721TiersHook hook)
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.QUEUE_RULESETS
        });

        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.SET_TERMINALS
        });

        // Deploy the hook.
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: projectId,
            deployTiersHookConfig: deployTiersHookConfig,
            salt: salt == bytes32(0) ? bytes32(0) : keccak256(abi.encode(_msgSender(), salt))
        });

        // Transfer the hook's ownership to the project.
        JBOwnable(address(hook)).transferOwnershipToProject(projectId);

        // Convert the 721 ruleset configurations to regular ruleset configurations.
        // Then modify the ruleset configurations to use this deployer as a wrapper for the datasouce.
        JBRulesetConfig[] memory rulesetConfigurations = _setup({
            projectId: projectId,
            rulesetConfigurations: _from721Config(launchRulesetsConfig.rulesetConfigurations, hook)
        });

        // Configure the rulesets.
        rulesetId = controller.launchRulesetsFor({
            projectId: projectId,
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: launchRulesetsConfig.terminalConfigurations,
            memo: launchRulesetsConfig.memo
        });
    }

    /// @notice Queues new rulesets for a project, using this contract as the data hook.
    /// @param projectId The ID of the project to queue the rulesets for.
    /// @param rulesetConfigurations The rulesets to queue.
    /// @param memo A memo to pass along to the emitted event.
    /// @return rulesetId The ID of the newly queued rulesets.
    function queueRulesetsOf(
        uint256 projectId,
        JBRulesetConfig[] calldata rulesetConfigurations,
        string calldata memo
    )
        external
        returns (uint256)
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.QUEUE_RULESETS
        });

        return CONTROLLER.queueRulesetsOf({
            projectId: projectId,
            rulesetConfigurations: _setup({projectId: projectId, rulesetConfigurations: rulesetConfigurations}),
            memo: memo
        });
    }

    /// @notice Queues new rulesets for a project with a 721 tiers hook attached, using this contract as the data hook.
    /// @param projectId The ID of the project to queue the rulesets for.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook which is being
    /// deployed.
    /// @param queueRulesetsConfig Configuration which dictates the behavior of the rulesets which are being queued.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return rulesetId The ID of the newly queued rulesets.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function queue721RulesetsOf(
        uint256 projectId,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBQueueRulesetsConfig calldata queueRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 rulesetId, IJB721TiersHook hook)
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.QUEUE_RULESETS
        });

        // Deploy the hook.
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: projectId,
            deployTiersHookConfig: deployTiersHookConfig,
            salt: salt == bytes32(0) ? bytes32(0) : keccak256(abi.encode(_msgSender(), salt))
        });

        // Convert the 721 ruleset configurations to regular ruleset configurations.
        // Then modify the ruleset configurations to use this deployer as a wrapper for the datasouce.
        JBRulesetConfig[] memory rulesetConfigurations = _setup({
            projectId: projectId,
            rulesetConfigurations: _from721Config(queueRulesetsConfig.rulesetConfigurations, hook)
        });

        // Configure the rulesets.
        rulesetId = controller.queueRulesetsOf({
            projectId: projectId,
            rulesetConfigurations: rulesetConfigurations,
            memo: queueRulesetsConfig.memo
        });
    }

    /// @dev Make sure this contract can only receive project NFTs from `JBProjects`.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        // Make sure the 721 received is from the `JBProjects` contract.
        if (msg.sender != address(PROJECTS)) revert();

        return IERC721Receiver.onERC721Received.selector;
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Sets up a project's rulesets.
    /// @param projectId The ID of the project to set up.
    /// @param rulesetConfigurations The rulesets to set up.
    /// @return rulesetConfigurations The rulesets that were set up.
    function _setup(
        uint256 projectId,
        JBRulesetConfig[] memory rulesetConfigurations
    )
        internal
        returns (JBRulesetConfig[] memory)
    {
        for (uint256 i; i < rulesetConfigurations.length; i++) {
            // Store the data hook.
            dataHookOf[projectId][block.timestamp + i] = JBDeployerHookConfig({
                useDataHookForPay: rulesetConfigurations[i].metadata.useDataHookForPay,
                useDataHookForCashOut: rulesetConfigurations[i].metadata.useDataHookForCashOut,
                dataHook: IJBRulesetDataHook(rulesetConfigurations[i].metadata.dataHook)
            });

            // Set this contract as the data hook.
            rulesetConfigurations[i].metadata.dataHook = address(this);
            rulesetConfigurations[i].metadata.useDataHookForCashOut = true;
        }

        return rulesetConfigurations;
    }

    /// @notice Converts a 721 ruleset configuration to a regular ruleset configuration.
    /// @param launchProjectConfig The 721 ruleset configuration to convert.
    /// @param dataHook The data hook to use for the ruleset.
    /// @return rulesetConfigurations The converted ruleset configuration.
    function _from721Config(
        JBPayDataHookRulesetConfig[] calldata launchProjectConfig,
        IJB721TiersHook dataHook
    )
        internal
        pure
        returns (JBRulesetConfig[] memory rulesetConfigurations)
    {
        rulesetConfigurations = new JBRulesetConfig[](launchProjectConfig.length);

        for (uint256 i; i < launchProjectConfig.length; i++) {
            JBPayDataHookRulesetMetadata calldata hookMetadata = launchProjectConfig[i].metadata;
            JBRulesetMetadata memory metadata = JBRulesetMetadata({
                // These fields are enforced as this is a 721 ruleset.
                useDataHookForPay: true,
                allowSetCustomToken: false,
                dataHook: address(dataHook),
                // These fields are present in the 721 metadata.
                reservedPercent: hookMetadata.reservedPercent,
                cashOutTaxRate: hookMetadata.cashOutTaxRate,
                baseCurrency: hookMetadata.baseCurrency,
                pausePay: hookMetadata.pausePay,
                pauseCreditTransfers: hookMetadata.pauseCreditTransfers,
                allowOwnerMinting: hookMetadata.allowOwnerMinting,
                allowTerminalMigration: hookMetadata.allowTerminalMigration,
                allowSetController: hookMetadata.allowSetController,
                allowSetTerminals: hookMetadata.allowSetTerminals,
                allowAddAccountingContext: hookMetadata.allowAddAccountingContext,
                allowAddPriceFeed: hookMetadata.allowAddPriceFeed,
                ownerMustSendPayouts: hookMetadata.ownerMustSendPayouts,
                holdFees: hookMetadata.holdFees,
                useTotalSurplusForCashOuts: hookMetadata.useTotalSurplusForCashOuts,
                useDataHookForCashOut: hookMetadata.useDataHookForCashOut,
                metadata: hookMetadata.metadata
            });

            rulesetConfigurations[i] = JBRulesetConfig({
                mustStartAtOrAfter: launchProjectConfig[i].mustStartAtOrAfter,
                duration: launchProjectConfig[i].duration,
                weight: launchProjectConfig[i].weight,
                weightCutPercent: launchProjectConfig[i].weightCutPercent,
                approvalHook: launchProjectConfig[i].approvalHook,
                metadata: metadata,
                splitGroups: launchProjectConfig[i].splitGroups,
                fundAccessLimitGroups: launchProjectConfig[i].fundAccessLimitGroups
            });
        }
    }

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
}
