// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// Foundry
import {Vm} from "forge-std/Vm.sol";
import {VmSafe} from "forge-std/Vm.sol";

// Helpers
import {Logger} from "script/deploy/helpers/Logger.sol";
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";
import {State, Execution, Contract, Root} from "script/deploy/helpers/DeploymentTypes.sol";

// Script Base
import {Base} from "script/deploy/Base.s.sol";

/// @title DeployManager
/// @notice Manages the deployment of contracts across multiple chains (Mainnet, Sonic).
/// @dev This contract orchestrates the deployment process by:
///      1. Reading deployment scripts from chain-specific folders
///      2. Dynamically loading and executing only the most recent scripts
///      3. Tracking deployment history in JSON files to avoid re-deployments
///      4. Supporting both fork testing and real deployments
contract DeployManager is Base {
    using Logger for bool;

    // Unique identifier for fork deployment files, based on timestamp.
    // Used to create separate deployment tracking files during fork tests.
    string public forkFileId;

    // Raw JSON content of the deployment file, loaded during setUp.
    // Contains the history of deployed contracts and executed scripts.
    string public deployment;

    // Maximum number of recent deployment scripts to process.
    // This improves efficiency by skipping older scripts that are already deployed,
    // avoiding unnecessary compilation and execution of historical deployment files.
    // Scripts are numbered (e.g., 001_, 002_...) and sorted alphabetically,
    // so only the last N scripts (most recent) will be considered for deployment.
    uint256 public maxDeploymentFiles = 10;

    /// @notice Initializes the deployment environment before running scripts.
    /// @dev Called automatically by Forge before run(). Sets up:
    ///      - Deployment state (FORK_TEST, FORK_DEPLOYING, or REAL_DEPLOYING)
    ///      - Logging configuration
    ///      - Deployment JSON file (creates if doesn't exist)
    ///      - Fork-specific deployment file (to avoid polluting main deployment history)
    ///      - Resolver contract for address lookups
    function setUp() external virtual {
        // Determine deployment state based on Forge context
        // (test, dry-run, broadcast, etc.)
        setState();

        // Enable logging for non-fork-test states, or if forcedLog is set
        // Fork tests typically run silently unless debugging
        log = state != State.FORK_TEST || forcedLog;

        // Log the chain name and ID for visibility
        log.logSetup(chainNames[block.chainid], block.chainid);
        log.logKeyValue("State", _stateToString(state));

        // Build path to chain-specific deployment file
        // e.g., "build/deployments-1.json" for mainnet
        string memory deployFilePath = getChainDeploymentFilePath();

        // Initialize deployment file with empty arrays if it doesn't exist
        // This ensures we always have a valid JSON structure to parse
        if (!vm.isFile(deployFilePath)) {
            vm.writeFile(deployFilePath, '{"contracts": [], "executions": []}');
            log.info(string.concat("Created deployment file at: ", deployFilePath));
            deployment = vm.readFile(deployFilePath);
        }

        // For fork states, create a separate deployment file to avoid
        // modifying the real deployment history during tests/dry-runs
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) {
            // Use timestamp as unique identifier for this fork session
            forkFileId = string(abi.encodePacked(vm.toString(block.timestamp)));

            // Pause tracing to reduce noise in test output
            vm.pauseTracing();

            // Copy current deployment data to fork-specific file
            deployment = vm.readFile(deployFilePath);
            vm.writeFile(getForkDeploymentFilePath(), deployment);

            vm.resumeTracing();
        } else if (state == State.REAL_DEPLOYING) {
            // For real deployments, read the existing deployment file
            deployment = vm.readFile(deployFilePath);
        }

        // Deploy the Resolver contract which provides address lookups
        // for previously deployed contracts
        deployResolver();
    }

    // ==================== Main Deployment Runner ==================== //

    /// @notice Main entry point for running deployment scripts.
    /// @dev Execution flow:
    ///      1. Load existing deployment history into Resolver
    ///      2. Determine the correct script folder based on chain ID
    ///      3. Read all script files from the folder (sorted alphabetically)
    ///      4. Process only the last N scripts (controlled by maxDeploymentFiles)
    ///      5. For each script: compile, deploy, and execute via _runDeployFile()
    ///      6. Save updated deployment history back to JSON
    function run() external virtual {
        // Load existing deployment data from JSON file into the Resolver
        _preDeployment();

        // Determine the deployment scripts folder path based on chain ID
        // - Chain ID 1 = Ethereum Mainnet -> use mainnet folder
        // - Chain ID 146 = Sonic -> use sonic folder
        // - Other chains = empty string (will revert)
        uint256 chainId = block.chainid;
        string memory path;
        if (chainId == 1) {
            path = string(abi.encodePacked(projectRoot, "/script/deploy/mainnet/"));
        } else if (chainId == 146) {
            path = string(abi.encodePacked(projectRoot, "/script/deploy/sonic/"));
        } else {
            revert("Unsupported chain");
        }

        // Read all files from the deployment scripts folder
        // Files are returned in alphabetical order (e.g., 001_..., 002_..., 003_...)
        vm.pauseTracing();
        VmSafe.DirEntry[] memory files = vm.readDir(path);

        // Calculate the starting index to only process the last N files
        // If we have more files than maxDeploymentFiles, start from (total - max)
        // Otherwise, start from 0 (process all files)
        uint256 startIndex = files.length > maxDeploymentFiles ? files.length - maxDeploymentFiles : 0;

        // Calculate how many files we'll actually process
        // Either maxDeploymentFiles or total files count, whichever is smaller
        uint256 resultSize = files.length > maxDeploymentFiles ? maxDeploymentFiles : files.length;

        // Iterate through the selected files (last N files in alphabetical order)
        for (uint256 i; i < resultSize; i++) {
            // Split the full file path by "/" to extract the filename
            // e.g., "/path/to/script/deploy/mainnet/015_UpgradeEthenaARMScript.sol"
            // ->    ["path", "to", ..., "015_UpgradeEthenaARMScript.sol"]
            string[] memory splitted = vm.split(files[startIndex + i].path, "/");
            string memory onlyName = vm.split(splitted[splitted.length - 1], ".")[0];

            // Deploy the script contract using vm.deployCode with just the filename
            // vm.deployCode compiles and deploys the contract, returning its address
            // Then call _runDeployFile to execute the deployment logic
            string memory contractName =
                string(abi.encodePacked(projectRoot, "/out/", onlyName, ".sol/$", onlyName, ".json"));
            _runDeployFile(address(vm.deployCode(contractName)));
        }
        vm.resumeTracing();

        // Save all deployment data from Resolver back to JSON file
        _postDeployment();
    }

    /// @notice Executes a single deployment script with proper state checks.
    /// @dev Implements a multi-step validation process:
    ///      1. Check if script is marked to skip
    ///      2. Check if governance proposal was already executed
    ///      3. Check if deployment was already run (in history)
    ///      4. Either handle pending governance proposal or run fresh deployment
    /// @param addr The address of the deployed AbstractDeployScript contract
    function _runDeployFile(address addr) internal {
        // Cast the address to AbstractDeployScript interface
        AbstractDeployScript deployFile = AbstractDeployScript(addr);

        // Skip if the script explicitly sets skip = true
        // Useful for temporarily disabling scripts without removing them
        if (deployFile.skip()) return;

        // Skip if the governance proposal for this script was already executed
        // This means the script's purpose has been fully accomplished
        if (deployFile.proposalExecuted()) return;

        // Get the script's unique name for history lookup
        string memory deployFileName = deployFile.name();

        // Check deployment history to see if this script was already run
        bool alreadyDeployed = resolver.executionExists(deployFileName);

        // Label the contract address for better trace readability in Forge
        vm.label(address(deployFile), deployFileName);

        // At this point, proposalExecuted is false, meaning the governance
        // proposal hasn't been finalized yet. Two scenarios:
        //
        // Scenario A: Script was deployed but proposal is still pending
        //   -> Only handle the governance proposal (don't re-deploy)
        //
        // Scenario B: Script was never deployed
        //   -> Run the full deployment

        if (alreadyDeployed) {
            // Scenario A: Deployment exists, just handle governance
            log.logSkip(deployFileName, "deployment already executed");
            log.info(string.concat("Handling governance proposal for ", deployFileName));
            deployFile.handleGovernanceProposal();
            return;
        }

        // Scenario B: Fresh deployment - run the script
        deployFile.run();
    }

    /// @notice Loads deployment history from JSON file into the Resolver.
    /// @dev Called at the start of run() to populate the Resolver with:
    ///      - Previously deployed contract addresses (for lookups via resolver.implementations())
    ///      - Previously executed script names (to avoid re-running deployments)
    ///      Uses pauseTracing modifier to reduce noise in Forge output.
    function _preDeployment() internal /*pauseTracing*/  {
        // Parse the JSON deployment file into structured data
        Root memory root = abi.decode(vm.parseJson(deployment), (Root));

        // Load all deployed contract addresses into the Resolver
        // This allows scripts to lookup addresses via resolver.implementations("CONTRACT_NAME")
        for (uint256 i = 0; i < root.contracts.length; i++) {
            resolver.addContract(root.contracts[i].name, root.contracts[i].implementation);
        }

        // Load all execution records into the Resolver
        // This tracks which scripts have already been run to prevent duplicates
        for (uint256 i = 0; i < root.executions.length; i++) {
            resolver.addExecution(root.executions[i].name, root.executions[i].timestamp);
        }
    }

    /// @notice Persists deployment data from Resolver back to JSON file.
    /// @dev Called at the end of run() to save:
    ///      - All contract addresses (existing + newly deployed)
    ///      - All execution records (existing + newly executed scripts)
    ///      Uses Forge's JSON serialization cheatcodes to build valid JSON.
    function _postDeployment() internal pauseTracing {
        // Fetch all data from the Resolver (includes new deployments)
        Contract[] memory contracts = resolver.getContracts();
        Execution[] memory executions = resolver.getExecutions();

        // Prepare arrays for JSON serialization
        string[] memory serializedContracts = new string[](contracts.length);
        string[] memory serializedExecutions = new string[](executions.length);

        // Serialize each contract as a JSON object: {"name": "...", "implementation": "0x..."}
        for (uint256 i = 0; i < contracts.length; i++) {
            vm.serializeString("c_obj", "name", contracts[i].name);
            serializedContracts[i] = vm.serializeAddress("c_obj", "implementation", contracts[i].implementation);
        }

        // Serialize each execution as a JSON object: {"name": "...", "timestamp": ...}
        for (uint256 i = 0; i < executions.length; i++) {
            vm.serializeString("e_obj", "name", executions[i].name);
            serializedExecutions[i] = vm.serializeUint("e_obj", "timestamp", executions[i].timestamp);
        }

        // Build the root JSON object with both arrays
        vm.serializeString("root", "contracts", serializedContracts);
        string memory finalJson = vm.serializeString("root", "executions", serializedExecutions);

        // Write to the appropriate file (fork file or real deployment file)
        vm.writeFile(getDeploymentFilePath(), finalJson);
    }

    // ==================== Helper Functions ==================== //

    /// @notice Determines the deployment state based on Forge execution context.
    /// @dev Maps Forge contexts to our State enum:
    ///      - FORK_TEST: Running tests, coverage, or snapshots (simulated, no real txs)
    ///      - FORK_DEPLOYING: Dry-run mode (simulated deployment for testing)
    ///      - REAL_DEPLOYING: Actual deployment with real transactions
    ///      Reverts if unable to determine the context (should never happen in Forge).
    function setState() public {
        state = State.DEFAULT;

        // TestGroup includes: forge test, forge coverage, forge snapshot
        if (vm.isContext(VmSafe.ForgeContext.TestGroup)) {
            state = State.FORK_TEST;
        }
        // ScriptDryRun: forge script WITHOUT --broadcast (simulation only)
        else if (vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) {
            state = State.FORK_DEPLOYING;
        }
        // ScriptResume: resuming a previously started broadcast
        else if (vm.isContext(VmSafe.ForgeContext.ScriptResume)) {
            state = State.REAL_DEPLOYING;
        }
        // ScriptBroadcast: forge script with --broadcast (real deployment)
        else if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            state = State.REAL_DEPLOYING;
        }

        require(state != State.DEFAULT, "Unable to determine deployment state");
    }

    /// @notice Deploys the Resolver contract to a deterministic address.
    /// @dev Uses vm.etch to place the Resolver bytecode at the predefined address.
    ///      This allows all scripts to access the same Resolver instance for
    ///      looking up previously deployed contract addresses.
    function deployResolver() public pauseTracing {
        // Get the compiled bytecode of the Resolver contract
        bytes memory resolverCode = vm.getDeployedCode("Resolver.sol:Resolver");

        // Place the bytecode at the resolver address (defined in Base contract)
        vm.etch(address(resolver), resolverCode);

        // Initialize the resolver with current state
        resolver.setState(state);

        // Label for better trace readability
        vm.label(address(resolver), "Resolver");
    }

    // ==================== Path Helper Functions ==================== //

    /// @notice Returns the path to the main deployment file for the current chain.
    /// @dev Format: "build/deployments-{chainId}.json"
    ///      Example: "build/deployments-1.json" for Ethereum Mainnet
    /// @return The full path to the deployment JSON file
    function getChainDeploymentFilePath() public view returns (string memory) {
        string memory chainIdStr = vm.toString(block.chainid);
        return string(abi.encodePacked(projectRoot, "/build/deployments-", chainIdStr, ".json"));
    }

    /// @notice Returns the path to the fork-specific deployment file.
    /// @dev Format: "build/deployments-fork-{timestamp}.json"
    ///      Used during fork tests to avoid modifying the real deployment history.
    /// @return The full path to the fork deployment JSON file
    function getForkDeploymentFilePath() public view returns (string memory) {
        return string(abi.encodePacked(projectRoot, "/build/deployments-fork-", forkFileId, ".json"));
    }

    /// @notice Returns the appropriate deployment file path based on current state.
    /// @dev Routes to fork file for testing/dry-runs, chain file for real deployments.
    /// @return The path to use for reading/writing deployment data
    function getDeploymentFilePath() public view returns (string memory) {
        // Fork states use temporary files to avoid polluting real deployment history
        if (state == State.FORK_TEST || state == State.FORK_DEPLOYING) {
            return getForkDeploymentFilePath();
        }
        // Real deployments write to the permanent chain-specific file
        if (state == State.REAL_DEPLOYING) {
            return getChainDeploymentFilePath();
        }
        revert("Invalid state");
    }

    /// @notice Converts a State enum value to its string representation.
    /// @dev Used for logging and debugging purposes.
    /// @param _state The state to convert
    /// @return Human-readable string representation of the state
    function _stateToString(State _state) internal pure returns (string memory) {
        if (_state == State.FORK_TEST) return "FORK_TEST";
        if (_state == State.FORK_DEPLOYING) return "FORK_DEPLOYING";
        if (_state == State.REAL_DEPLOYING) return "REAL_DEPLOYING";
        return "DEFAULT";
    }
}
