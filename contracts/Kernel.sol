// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "hardhat/console.sol"; // Keep this for logging

//============================================================================================//
//                                        GLOBAL TYPES                                        //
//============================================================================================//

enum Actions {
    InstallModule,
    UpgradeModule,
    ActivatePolicy,
    DeactivatePolicy,
    ChangeExecutor,
    MigrateKernel,
    ExecuteAction  
}

struct Instruction {
    Actions action;
    address target;
}

struct Permissions {
    Keycode keycode;
    bytes4 funcSelector;
}

type Keycode is bytes5;

//============================================================================================//
//                                       UTIL FUNCTIONS                                       //
//============================================================================================//

error TargetNotAContract(address target_);
error InvalidKeycode(Keycode keycode_);

function toKeycode(bytes5 keycode_) pure returns (Keycode) {
    return Keycode.wrap(keycode_);
}

function fromKeycode(Keycode keycode_) pure returns (bytes5) {
    return Keycode.unwrap(keycode_);
}

function ensureContract(address target_) view {
    if (target_.code.length == 0) revert TargetNotAContract(target_);
}

function ensureValidKeycode(Keycode keycode_) pure {
    bytes5 unwrapped = Keycode.unwrap(keycode_);
    for (uint256 i = 0; i < 5; ) {
        bytes1 char = unwrapped[i];
        if (char < 0x41 || char > 0x5A) revert InvalidKeycode(keycode_); // A-Z only
        unchecked {
            i++;
        }
    }
}



//============================================================================================//
//                                        COMPONENTS                                          //
//============================================================================================//

abstract contract KernelAdapter {
    error KernelAdapter_OnlyKernel(address caller_);

    Kernel public kernel;

    constructor(Kernel kernel_) {
        kernel = kernel_;
    }

    modifier onlyKernel() {
        if (msg.sender != address(kernel)) revert KernelAdapter_OnlyKernel(msg.sender);
        _;
    }

    function changeKernel(Kernel newKernel_) external onlyKernel {
        kernel = newKernel_;
    }
}

abstract contract Module is KernelAdapter {
    error Module_PolicyNotPermitted(address policy_);

    constructor(Kernel kernel_) KernelAdapter(kernel_) {}

    modifier permissioned() {
        if (
            msg.sender == address(kernel) ||
            !kernel.modulePermissions(KEYCODE(), Policy(msg.sender), msg.sig)
        ) revert Module_PolicyNotPermitted(msg.sender);
        _;
    }

    function KEYCODE() public pure virtual returns (Keycode) {}
    function VERSION() external pure virtual returns (uint8 major, uint8 minor) {}
    function INIT() external virtual onlyKernel {}
}

abstract contract Policy is KernelAdapter {
    error Policy_ModuleDoesNotExist(Keycode keycode_);

    constructor(Kernel kernel_) KernelAdapter(kernel_) {}

    function isActive() external view returns (bool) {
        return kernel.isPolicyActive(this);
    }

    function getModuleAddress(Keycode keycode_) internal view returns (address) {
        address moduleForKeycode = address(kernel.getModuleForKeycode(keycode_));
        if (moduleForKeycode == address(0)) revert Policy_ModuleDoesNotExist(keycode_);
        return moduleForKeycode;
    }

    function configureDependencies() external virtual returns (Keycode[] memory dependencies) {}
    function requestPermissions() external view virtual returns (Permissions[] memory requests) {}
}

contract Kernel is AccessControl {
    event PermissionsUpdated(
        Keycode indexed keycode_,
        Policy indexed policy_,
        bytes4 funcSelector_,
        bool granted_
    );
    event ActionExecuted(Actions indexed action_, address indexed target_);
    event ModuleFunctionExecuted(address indexed module, bytes4 indexed functionSelector);

    error Kernel_ModuleFunctionReverted(address module, bytes reason);
    error Kernel_OnlyExecutor(address caller_);
    error Kernel_ModuleAlreadyInstalled(Keycode module_);
    error Kernel_InvalidModuleUpgrade(Keycode module_);
    error Kernel_PolicyAlreadyActivated(address policy_);
    error Kernel_PolicyNotActivated(address policy_);

    address public executor;
    Keycode[] public allKeycodes;
    mapping(Keycode => Module) public getModuleForKeycode;
    mapping(Module => Keycode) public getKeycodeForModule;
    mapping(Keycode => Policy[]) public moduleDependents;
    mapping(Keycode => mapping(Policy => uint256)) public getDependentIndex;
    mapping(Keycode => mapping(Policy => mapping(bytes4 => bool))) public modulePermissions;
    Policy[] public activePolicies;
    mapping(Policy => uint256) public getPolicyIndex;

    constructor() {
        executor = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Granting the deployer DEFAULT_ADMIN_ROLE
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert Kernel_OnlyExecutor(msg.sender);
        _;
    }

    function isPolicyActive(Policy policy_) public view returns (bool) {
        return activePolicies.length > 0 && activePolicies[getPolicyIndex[policy_]] == policy_;
    }

    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // Execute Actions
    function executeAction(
        Actions action_,
        address target_,
        bytes memory data_
    ) external onlyExecutor nonReentrant {
        ensureContract(target_);

        if (action_ == Actions.InstallModule) {
            ensureValidKeycode(Module(target_).KEYCODE());
            _installModule(Module(target_));
        } else if (action_ == Actions.UpgradeModule) {
            ensureValidKeycode(Module(target_).KEYCODE());
            _upgradeModule(Module(target_));
        } else if (action_ == Actions.ActivatePolicy) {
            _activatePolicy(Policy(target_));
        } else if (action_ == Actions.DeactivatePolicy) {
            _deactivatePolicy(Policy(target_));
        } else if (action_ == Actions.ChangeExecutor) {
            require(target_ != address(0), "Kernel: invalid executor address");
            executor = target_;
        } else if (action_ == Actions.MigrateKernel) {
            require(target_ != address(this), "Kernel: cannot migrate to self");
            _migrateKernel(Kernel(target_));
        } else if (action_ == Actions.ExecuteAction) {
            _executeModuleFunction(target_, data_);
        } else {
            revert("Kernel: invalid action");
        }

        emit ActionExecuted(action_, target_);
    }

    // Installation of modules
    function _installModule(Module newModule_) internal {
        Keycode keycode = newModule_.KEYCODE();
        console.log("INSTALL: Keycode: ", string(abi.encodePacked(fromKeycode(keycode))));

        require(Keycode.unwrap(keycode) != bytes5(0), "Kernel: invalid keycode");

        if (address(getModuleForKeycode[keycode]) != address(0))
            revert Kernel_ModuleAlreadyInstalled(keycode);

        getModuleForKeycode[keycode] = newModule_; // Store the module for the keycode
        getKeycodeForModule[newModule_] = keycode; // Store the reverse mapping

        newModule_.INIT(); // Call INIT on the new module
    }


    // Policy activation
    function _activatePolicy(Policy policy_) internal {
        if (isPolicyActive(policy_)) revert Kernel_PolicyAlreadyActivated(address(policy_));

        activePolicies.push(policy_);
        getPolicyIndex[policy_] = activePolicies.length - 1;

        Keycode[] memory dependencies = policy_.configureDependencies();
        for (uint256 i = 0; i < dependencies.length; ++i) {
            moduleDependents[dependencies[i]].push(policy_);
        }

        Permissions[] memory requests = policy_.requestPermissions();
        _setPolicyPermissions(policy_, requests, true);
    }

    // Policy deactivation
    function _deactivatePolicy(Policy policy_) internal {
        if (!isPolicyActive(policy_)) revert Kernel_PolicyNotActivated(address(policy_));

        Permissions[] memory requests = policy_.requestPermissions();
        _setPolicyPermissions(policy_, requests, false);

        uint256 idx = getPolicyIndex[policy_];
        Policy lastPolicy = activePolicies[activePolicies.length - 1];

        activePolicies[idx] = lastPolicy;
        activePolicies.pop();
        getPolicyIndex[lastPolicy] = idx;
        delete getPolicyIndex[policy_];

        _pruneFromDependents(policy_);
    }

    function _setPolicyPermissions(
        Policy policy_,
        Permissions[] memory requests_,
        bool grant_
    ) internal {
        uint256 reqLength = requests_.length;
        for (uint256 i = 0; i < reqLength; ) {
            Permissions memory request = requests_[i];
            
            // Add logging here to track permission granting
            console.log("KERNEL: Granting permission for policy:", address(policy_));
            console.log("KERNEL: Module Keycode:", string(abi.encodePacked(fromKeycode(request.keycode))));
            console.log("KERNEL: Function selector:", bytes4ToHex(request.funcSelector));
            console.log("KERNEL: Granting:", grant_);
            
            // Update the permission mapping
            modulePermissions[request.keycode][policy_][request.funcSelector] = grant_;
            
            emit PermissionsUpdated(request.keycode, policy_, request.funcSelector, grant_);

            unchecked {
                ++i;
            }
        }
    }



    function _executeModuleFunction(address module_, bytes memory data_) internal {
        (bool success, bytes memory result) = module_.call(data_);
        if (!success) {
            revert Kernel_ModuleFunctionReverted(module_, result);
        }
        emit ModuleFunctionExecuted(module_, bytes4(data_));
    }


    function _upgradeModule(Module newModule_) internal {
        Keycode keycode = newModule_.KEYCODE();
        Module oldModule = getModuleForKeycode[keycode];

        // Ensure the module being upgraded already exists and that it's not the same as the new module
        if (address(oldModule) == address(0) || oldModule == newModule_)
            revert Kernel_InvalidModuleUpgrade(keycode);

        // Remove the old module and install the new one
        getKeycodeForModule[oldModule] = Keycode.wrap(bytes5(0));
        getKeycodeForModule[newModule_] = keycode;
        getModuleForKeycode[keycode] = newModule_;

        // Initialize the new module
        newModule_.INIT();

        // Reconfigure the policies that depend on the upgraded module
        _reconfigurePolicies(keycode);
    }

    function _reconfigurePolicies(Keycode keycode_) internal {
        Policy[] memory dependents = moduleDependents[keycode_];
        uint256 depLength = dependents.length;

        for (uint256 i; i < depLength; ) {
            dependents[i].configureDependencies();

            unchecked {
                ++i;
            }
        }
    }


    function _migrateKernel(Kernel newKernel_) internal {
        require(address(newKernel_) != address(0), "Kernel: invalid new kernel address");

        // Transfer all modules to the new kernel
        for (uint256 i = 0; i < allKeycodes.length; i++) {
            Module module = Module(getModuleForKeycode[allKeycodes[i]]);
            module.changeKernel(newKernel_);
        }

        // Transfer all policies to the new kernel
        for (uint256 j = 0; j < activePolicies.length; j++) {
            Policy policy = activePolicies[j];
            policy.changeKernel(newKernel_);
        }

        // Transfer ownership of modules and policies to the new kernel
        newKernel_.acceptMigration(allKeycodes, activePolicies);
    }

    function setModulePermission(
        address module,
        address policy,
        bytes4 selector,
        bool granted
    ) external onlyExecutor {
        Keycode keycode = getKeycodeForModule[Module(module)];
        require(Keycode.unwrap(keycode) != bytes5(0), "Invalid Keycode");
        modulePermissions[keycode][Policy(policy)][selector] = granted;

        emit PermissionsUpdated(keycode, Policy(policy), selector, granted);
    }

function bytes4ToHex(bytes4 _bytes) internal pure returns (string memory) {
    return string(abi.encodePacked(
        "0x",
        toHexDigit(uint8(_bytes[0] >> 4)),
        toHexDigit(uint8(_bytes[0] & 0x0f)),
        toHexDigit(uint8(_bytes[1] >> 4)),
        toHexDigit(uint8(_bytes[1] & 0x0f)),
        toHexDigit(uint8(_bytes[2] >> 4)),
        toHexDigit(uint8(_bytes[2] & 0x0f)),
        toHexDigit(uint8(_bytes[3] >> 4)),
        toHexDigit(uint8(_bytes[3] & 0x0f))
    ));
}

function bytes5ToHex(bytes5 _bytes) internal pure returns (string memory) {
    return string(abi.encodePacked(
        "0x",
        toHexDigit(uint8(_bytes[0] >> 4)),
        toHexDigit(uint8(_bytes[0] & 0x0f)),
        toHexDigit(uint8(_bytes[1] >> 4)),
        toHexDigit(uint8(_bytes[1] & 0x0f)),
        toHexDigit(uint8(_bytes[2] >> 4)),
        toHexDigit(uint8(_bytes[2] & 0x0f)),
        toHexDigit(uint8(_bytes[3] >> 4)),
        toHexDigit(uint8(_bytes[3] & 0x0f)),
        toHexDigit(uint8(_bytes[4] >> 4)),
        toHexDigit(uint8(_bytes[4] & 0x0f))
    ));
}

function toHexDigit(uint8 d) internal pure returns (bytes1) {
    if (0 <= d && d <= 9) {
        return bytes1(uint8(bytes1("0")) + d);
    } else if (10 <= uint8(d) && uint8(d) <= 15) {
        return bytes1(uint8(bytes1("a")) + d - 10);
    }
    revert("Invalid hex digit");
}



    function acceptMigration(Keycode[] memory keycodes_, Policy[] memory policies_) external {
        require(msg.sender == executor, "Kernel: only executor can accept migration");

        // Process the incoming migration by registering the modules and policies
        for (uint256 i = 0; i < keycodes_.length; i++) {
            Keycode keycode = keycodes_[i];
            Module module = Module(getModuleForKeycode[keycode]);
            getModuleForKeycode[keycode] = module;
            allKeycodes.push(keycode);
        }

        for (uint256 j = 0; j < policies_.length; j++) {
            Policy policy = policies_[j];
            activePolicies.push(policy);
            getPolicyIndex[policy] = activePolicies.length - 1;
        }
    }


    function _pruneFromDependents(Policy policy_) internal {
        Keycode[] memory dependencies = policy_.configureDependencies();
        uint256 depcLength = dependencies.length;

        for (uint256 i; i < depcLength; ) {
            Keycode keycode = dependencies[i];
            Policy[] storage dependents = moduleDependents[keycode];

            uint256 origIndex = getDependentIndex[keycode][policy_];
            Policy lastPolicy = dependents[dependents.length - 1];

            dependents[origIndex] = lastPolicy;
            dependents.pop();

            getDependentIndex[keycode][lastPolicy] = origIndex;
            delete getDependentIndex[keycode][policy_];

            unchecked {
                ++i;
            }
        }
    }
}
