// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

//============================================================================================//
//                                        GLOBAL TYPES                                        //
//============================================================================================//

enum Actions {
    InstallModule,
    UpgradeModule,
    ActivatePolicy,
    DeactivatePolicy,
    ChangeExecutor,
    MigrateKernel
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

contract Kernel {
    event PermissionsUpdated(
        Keycode indexed keycode_,
        Policy indexed policy_,
        bytes4 funcSelector_,
        bool granted_
    );
    event ActionExecuted(Actions indexed action_, address indexed target_);

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
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert Kernel_OnlyExecutor(msg.sender);
        _;
    }

    function isPolicyActive(Policy policy_) public view returns (bool) {
        return activePolicies.length > 0 && activePolicies[getPolicyIndex[policy_]] == policy_;
    }

    function executeAction(Actions action_, address target_) external onlyExecutor {
        if (action_ == Actions.InstallModule) {
            ensureContract(target_);
            ensureValidKeycode(Module(target_).KEYCODE());
            _installModule(Module(target_));
        } else if (action_ == Actions.UpgradeModule) {
            ensureContract(target_);
            ensureValidKeycode(Module(target_).KEYCODE());
            _upgradeModule(Module(target_));
        } else if (action_ == Actions.ActivatePolicy) {
            ensureContract(target_);
            _activatePolicy(Policy(target_));
        } else if (action_ == Actions.DeactivatePolicy) {
            ensureContract(target_);
            _deactivatePolicy(Policy(target_));
        } else if (action_ == Actions.ChangeExecutor) {
            executor = target_;
        } else if (action_ == Actions.MigrateKernel) {
            ensureContract(target_);
            _migrateKernel(Kernel(target_));
        }

        emit ActionExecuted(action_, target_);
    }

    function _installModule(Module newModule_) internal {
        Keycode keycode = newModule_.KEYCODE();

        if (address(getModuleForKeycode[keycode]) != address(0))
            revert Kernel_ModuleAlreadyInstalled(keycode);

        getModuleForKeycode[keycode] = newModule_;
        getKeycodeForModule[newModule_] = keycode;
        allKeycodes.push(keycode);

        newModule_.INIT();
        
    }


    function _upgradeModule(Module newModule_) internal {
        Keycode keycode = newModule_.KEYCODE();
        Module oldModule = getModuleForKeycode[keycode];

        if (address(oldModule) == address(0) || oldModule == newModule_)
            revert Kernel_InvalidModuleUpgrade(keycode);

        getKeycodeForModule[oldModule] = Keycode.wrap(bytes5(0));
        getKeycodeForModule[newModule_] = keycode;
        getModuleForKeycode[keycode] = newModule_;

        newModule_.INIT();

        _reconfigurePolicies(keycode);
    }

    function _activatePolicy(Policy policy_) internal {
        if (isPolicyActive(policy_)) revert Kernel_PolicyAlreadyActivated(address(policy_));

        activePolicies.push(policy_);
        getPolicyIndex[policy_] = activePolicies.length - 1;

        Keycode[] memory dependencies = policy_.configureDependencies();
        uint256 depLength = dependencies.length;

        for (uint256 i; i < depLength; ) {
            Keycode keycode = dependencies[i];

            moduleDependents[keycode].push(policy_);
            getDependentIndex[keycode][policy_] = moduleDependents[keycode].length - 1;

            unchecked {
                ++i;
            }
        }

        Permissions[] memory requests = policy_.requestPermissions();
        _setPolicyPermissions(policy_, requests, true);
    }

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

    function _migrateKernel(Kernel newKernel_) internal {
        uint256 keycodeLen = allKeycodes.length;
        for (uint256 i; i < keycodeLen; ) {
            Module module = Module(getModuleForKeycode[allKeycodes[i]]);
            module.changeKernel(newKernel_);
            unchecked {
                ++i;
            }
        }

        uint256 policiesLen = activePolicies.length;
        for (uint256 j; j < policiesLen; ) {
            Policy policy = activePolicies[j];
            policy.changeKernel(newKernel_);
            unchecked {
                ++j;
            }
        }
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

    function _setPolicyPermissions(
        Policy policy_,
        Permissions[] memory requests_,
        bool grant_
    ) internal {
        uint256 reqLength = requests_.length;
        for (uint256 i = 0; i < reqLength; ) {
            Permissions memory request = requests_[i];
            modulePermissions[request.keycode][policy_][request.funcSelector] = grant_;

            emit PermissionsUpdated(request.keycode, policy_, request.funcSelector, grant_);

            unchecked {
                ++i;
            }
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