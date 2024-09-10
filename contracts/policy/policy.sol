// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../controller/ctrl.sol";

contract policy is AccessControl, Pausable {
    bytes32 public constant POLICY_ROLE = keccak256("POLICY_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    ctrl public immutable controller;
    IERC20 public immutable debaseToken;
    IERC20 public immutable stakingToken;

    event PolicyActionExecuted(string action, address executor);

    constructor(address _controller, address _debaseToken, address _stakingToken) {
        require(_controller != address(0), "Invalid controller address");
        require(_debaseToken != address(0), "Invalid DEBASE token address");
        require(_stakingToken != address(0), "Invalid staking token address");

        controller = ctrl(_controller);
        debaseToken = IERC20(_debaseToken);
        stakingToken = IERC20(_stakingToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(POLICY_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }

    modifier onlyPolicyOrExecutor() {
        require(hasRole(POLICY_ROLE, msg.sender) || hasRole(EXECUTOR_ROLE, msg.sender), "Caller is not authorized");
        _;
    }

    // Token operations
    function mint(address to, uint256 amount) external onlyRole(POLICY_ROLE) whenNotPaused {
    require(to != address(0), "Invalid address for minting");
    require(amount > 0, "Amount must be greater than zero");
    require(address(controller) != address(0), "Controller address is not set correctly");

    controller.mint(to, amount);
    emit PolicyActionExecuted("Mint", msg.sender);
    }



    function burn(uint256 amount) external whenNotPaused {
        require(debaseToken.balanceOf(msg.sender) >= amount, "Insufficient balance");
        controller.burn(msg.sender, amount);
        emit PolicyActionExecuted("Burn", msg.sender);
    }

    function debase() external onlyRole(POLICY_ROLE) whenNotPaused {
        controller.debase();
        emit PolicyActionExecuted("Debase", msg.sender);
    }

    // Staking operations
    function stake(uint256 amount) external whenNotPaused {
        require(stakingToken.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(stakingToken.allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        stakingToken.transferFrom(msg.sender, address(this), amount);
        stakingToken.approve(address(controller), amount);
        controller.stake(msg.sender, amount);
        emit PolicyActionExecuted("Stake", msg.sender);
    }

    function unstake(uint256 amount) external whenNotPaused {
        controller.unstake(msg.sender, amount);
        emit PolicyActionExecuted("Unstake", msg.sender);
    }

    function claimReward() external whenNotPaused {
        controller.claimReward(msg.sender);
        emit PolicyActionExecuted("ClaimReward", msg.sender);
    }

    // Bonding operations
    function createBond(uint256 deposit, bool isPartnerToken) external whenNotPaused {
        IERC20 depositToken = isPartnerToken ? IERC20(controller.bondingContract().partnerToken()) : debaseToken;
        require(depositToken.balanceOf(msg.sender) >= deposit, "Insufficient balance");
        require(depositToken.allowance(msg.sender, address(this)) >= deposit, "Insufficient allowance");
        depositToken.transferFrom(msg.sender, address(this), deposit);
        depositToken.approve(address(controller), deposit);
        controller.createBond(msg.sender, deposit, isPartnerToken);
        emit PolicyActionExecuted("CreateBond", msg.sender);
    }

    function redeemBond() external whenNotPaused {
        controller.redeemBond(msg.sender);
        emit PolicyActionExecuted("RedeemBond", msg.sender);
    }

    // Admin functions
    function setDiscount(bool isPartnerToken, uint256 newDiscount) external onlyRole(POLICY_ROLE) whenNotPaused {
        controller.setBondingDiscount(isPartnerToken, newDiscount);
        emit PolicyActionExecuted("SetDiscount", msg.sender);
    }

    function setStakingAPY(uint256 newBaseAPY, uint256 newBoostAPY) external onlyRole(POLICY_ROLE) whenNotPaused {
        controller.setStakingAPY(newBaseAPY, newBoostAPY);
        emit PolicyActionExecuted("SetStakingAPY", msg.sender);
    }

    function activateStakingBoost(uint256 duration) external onlyRole(POLICY_ROLE) whenNotPaused {
        controller.activateStakingBoost(duration);
        emit PolicyActionExecuted("ActivateStakingBoost", msg.sender);
    }

    function pause() external onlyRole(POLICY_ROLE) {
        _pause();
        emit PolicyActionExecuted("Pause", msg.sender);
    }

    function unpause() external onlyRole(POLICY_ROLE) {
        _unpause();
        emit PolicyActionExecuted("Unpause", msg.sender);
    }

    // Emergency function
    function executeEmergencyAction(address target, bytes calldata data) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success, ) = target.call(data);
        require(success, "Emergency action failed");
        emit PolicyActionExecuted("EmergencyAction", msg.sender);
    }
}