
// STAKE Contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract STAKE is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant POLICY_ROLE = keccak256("POLICY_ROLE");

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 rewardDebt;
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;
    uint256 public baseAPY = 1333;  // Base APY in basis points (13.33%)
    uint256 public boostAPY = 8888; // Boosted APY in basis points (88.88%)
    bool public boostActive = false;
    uint256 public boostEndTime;

    uint256 public constant MAX_APY = 10000; // 100% in basis points

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event APYUpdated(uint256 newBaseAPY, uint256 newBoostAPY);
    event BoostActivated(uint256 endTime);

    constructor(address _stakingToken, address _rewardToken) {
        require(_stakingToken != address(0), "Invalid staking token address");
        require(_rewardToken != address(0), "Invalid reward token address");
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);
        _grantRole(POLICY_ROLE, msg.sender);
    }

    function stake(address user, uint256 amount) external onlyRole(CONTROLLER_ROLE) whenNotPaused nonReentrant {
        require(amount > 0, "Stake amount must be greater than zero");
        _updateReward(user);

        stakes[user].amount += amount;
        stakes[user].timestamp = block.timestamp;
        totalStaked += amount;
        
        emit Staked(user, amount);
    }

    function unstake(address user, uint256 amount) external onlyRole(CONTROLLER_ROLE) whenNotPaused nonReentrant {
        require(stakes[user].amount >= amount, "Insufficient staked balance");

        _updateReward(user);
        
        stakes[user].amount -= amount;
        totalStaked -= amount;
        
        emit Unstaked(user, amount);
    }

    function claimReward(address user) external onlyRole(CONTROLLER_ROLE) whenNotPaused nonReentrant returns (uint256) {
        _updateReward(user);

        uint256 reward = stakes[user].rewardDebt;
        require(reward > 0, "No rewards to claim");
        
        stakes[user].rewardDebt = 0;
        emit RewardClaimed(user, reward);
        return reward;
    }

    function _updateReward(address user) internal {
        uint256 reward = calculateReward(user);
        if (reward > 0) {
            stakes[user].rewardDebt += reward;
        }
        stakes[user].timestamp = block.timestamp;
    }

    function calculateReward(address user) public view returns (uint256) {
        Stake memory userStake = stakes[user];
        if (userStake.amount == 0) return 0;

        uint256 duration = block.timestamp - userStake.timestamp;
        uint256 apy = boostActive && block.timestamp < boostEndTime ? boostAPY : baseAPY;
        
        // Increase the reward rate for testing purposes
        return (userStake.amount * apy * duration) / (1 days * 100);
    }

    function setAPY(uint256 newBaseAPY, uint256 newBoostAPY) external onlyRole(POLICY_ROLE) {
        require(newBaseAPY <= MAX_APY && newBoostAPY <= MAX_APY, "APY cannot exceed 100%");
        baseAPY = newBaseAPY;
        boostAPY = newBoostAPY;
        emit APYUpdated(newBaseAPY, newBoostAPY);
    }

    function activateBoost(uint256 duration) external onlyRole(POLICY_ROLE) {
        boostActive = true;
        boostEndTime = block.timestamp + duration;
        emit BoostActivated(boostEndTime);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}