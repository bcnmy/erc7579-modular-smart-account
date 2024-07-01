// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ==========================
// Standard Library Imports
// ==========================
import "forge-std/src/console2.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";

// ==========================
// Utility Libraries
// ==========================
import "solady/src/utils/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ==========================
// Account Abstraction Imports
// ==========================
import { EntryPoint } from "account-abstraction/contracts/core/EntryPoint.sol";
import { IEntryPoint } from "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "account-abstraction/contracts/interfaces/PackedUserOperation.sol";

// ==========================
// ModeLib Import
// ==========================
import "../../../contracts/lib/ModeLib.sol";
import "../../../contracts/lib/ExecLib.sol";
import "../../../contracts/lib/ModuleTypeLib.sol";

// ==========================
// Interface Imports
// ==========================
import "../../../contracts/interfaces/base/IAccountConfig.sol";
import "../../../contracts/interfaces/base/IModuleManager.sol";
import "../../../contracts/interfaces/modules/IModule.sol";
import "../../../contracts/interfaces/modules/IExecutor.sol";
import "../../../contracts/interfaces/base/IStorage.sol";
import "../../../contracts/interfaces/INexus.sol";

// ==========================
// Contract Implementations
// ==========================
import "../../../contracts/Nexus.sol";
import "../../../contracts/factory/NexusAccountFactory.sol";
import "./../../../contracts/modules/validators/K1Validator.sol";
import "../../../contracts/common/Stakeable.sol";

// ==========================
// Mock Contracts for Testing
// ==========================
import { MockPaymaster } from "../../../contracts/mocks/MockPaymaster.sol";
import { MockInvalidModule } from "./../../../contracts/mocks/MockInvalidModule.sol";
import { MockExecutor } from "../../../contracts/mocks/MockExecutor.sol";
import { MockHandler } from "../../../contracts/mocks/MockHandler.sol";
import { MockValidator } from "../../../contracts/mocks/MockValidator.sol";
import { MockHook } from "../../../contracts/mocks/MockHook.sol";
import { MockToken } from "../../../contracts/mocks/MockToken.sol";
import "../../../contracts/mocks/MockNFT.sol";
import "../../../contracts/mocks/Counter.sol";

// ==========================
// Additional Contract Imports
// ==========================
import "./../../../contracts/factory/K1ValidatorFactory.sol";
import "./../../../contracts/utils/RegistryBootstrap.sol";
import "./../../../contracts/lib/BootstrapLib.sol";
import "../../../contracts/mocks/MockNFT.sol";
import "../../../contracts/mocks/MockToken.sol";

// ==========================
// Sentinel List Helper
// ==========================
import { SentinelListLib } from "sentinellist/src/SentinelList.sol";
import { SentinelListHelper } from "sentinellist/src/SentinelListHelper.sol";

// ==========================
// Helper and Struct Imports
// ==========================
import "./TestHelper.t.sol";

contract Imports {
// This contract acts as a single point of import for Foundry tests.
// It does not require any logic, as its sole purpose is to consolidate imports.
}
