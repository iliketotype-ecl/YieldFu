// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../Kernel.sol";
import "../YieldFu.sol";
import "./MINTR.sol";

contract STAKE is Module, Pausable, ReentrancyGuard {
    // =========  EVENTS ========= //
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event APYChanged(uint256 newBaseAPY, uint256 newBoostedAPY);
    event APYBoosted(uint256 boostEndTime);
    event CooldownSet(uint256 newCooldown);
    event EarlyUnstakeSlashSet(uint256 newSlashRate);
    event MaxStakeCapSet(uint256 newMaxStakeCap);

    // ========= ERRORS ========= //
    error STAKE_ZeroAmount();
    error STAKE_InsufficientBalance();
    error STAKE_CooldownNotMet();
    error STAKE_MaxStakeCapExceeded();
    error STAKE_InvalidAPY();
    error STAKE_InvalidCooldown();
    error STAKE_InvalidSlashRate();

    // =========  STATE ========= //
    YieldFuToken public token;
    MINTR public mintrModule;
    uint256 public baseAPY;
    uint256 public boostedAPY;
    uint256 public boostEndTime;
    uint256 public cooldownPeriod;
    uint256 public earlyUnstakeSlashRate;
    uint256 public maxStakeCap;
    uint256 public totalStaked;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    struct StakeInfo {
        uint256 amount;
        uint256 lastStakeTime;
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    mapping(address => StakeInfo) public stakes;

    constructor(
        Kernel kernel_,
        YieldFuToken token_,
        uint256 initialBaseAPY_,
        uint256 initialBoostedAPY_,
        uint256 initialCooldown_,
        uint256 initialSlashRate_,
        uint256 initialMaxStakeCap_
    ) Module(kernel_) {
        token = token_;
        baseAPY = initialBaseAPY_;
        boostedAPY = initialBoostedAPY_;
        cooldownPeriod = initialCooldown_;
        earlyUnstakeSlashRate = initialSlashRate_;
        maxStakeCap = initialMaxStakeCap_;
        lastUpdateTime = block.timestamp;
        rewardRate = baseAPY * 1e18 / (365 days * 100);
    }

    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("STAKE");
    }

    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 2); // v1.2
    }

    function INIT() external override onlyKernel {
        // Initialization logic, if any
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            stakes[account].rewards = earned(account);
            stakes[account].userRewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        uint256 newRewardPerToken = rewardPerTokenStored + (
            timeElapsed * rewardRate * 1e18 / totalStaked
        );
        return newRewardPerToken;
    }

    function earned(address account) public view returns (uint256) {
        uint256 rewardPerTokenDelta = rewardPerToken() - stakes[account].userRewardPerTokenPaid;
        uint256 newReward = (stakes[account].amount * rewardPerTokenDelta / 1e18);
        uint256 totalReward = newReward + stakes[account].rewards;
        console.log("STAKE: Total reward for", account, "is", totalReward);
        return totalReward;
    }

    function stake(address from, uint256 amount) external nonReentrant whenNotPaused permissioned updateReward(from) {
        if (amount == 0) revert STAKE_ZeroAmount();
        if (totalStaked + amount > maxStakeCap) revert STAKE_MaxStakeCapExceeded();

        stakes[from].amount += amount;
        stakes[from].lastStakeTime = block.timestamp;
        totalStaked += amount;

        token.transferFrom(from, address(this), amount);
        emit Stake(from, amount);
    }

    function unstake(address from, uint256 amount) external nonReentrant whenNotPaused permissioned updateReward(from) {
        StakeInfo storage userStake = stakes[from];
        if (amount == 0) revert STAKE_ZeroAmount();
        if (userStake.amount < amount) revert STAKE_InsufficientBalance();

        uint256 slashAmount = 0;
        if (block.timestamp < userStake.lastStakeTime + cooldownPeriod) {
            slashAmount = (amount * earlyUnstakeSlashRate) / 10000;
        }

        userStake.amount -= amount;
        totalStaked -= amount;

        uint256 transferAmount = amount - slashAmount;
        token.transfer(from, transferAmount);
        if (slashAmount > 0) {
            token.burn(slashAmount);
        }

        emit Unstake(from, amount);
    }

    // Claim reward and mint the corresponding tokens via MINTR module
    function getReward() external nonReentrant whenNotPaused permissioned updateReward(msg.sender) {
        
        uint256 reward = stakes[msg.sender].rewards;
        console.log("MINTR: Minting reward of", reward, "to", msg.sender);

        if (reward > 0) {
            // Reset the rewards before minting
            stakes[msg.sender].rewards = 0;

            // Use the MINTR module to mint the reward to the user
            mintrModule.mint(msg.sender, reward);

            emit RewardPaid(msg.sender, reward);
        }
    }



    function getCurrentAPY() public view returns (uint256) {
        return block.timestamp < boostEndTime ? boostedAPY : baseAPY;
    }

    function setAPY(uint256 newBaseAPY, uint256 newBoostedAPY) external permissioned updateReward(address(0)) {
        if (newBaseAPY > 10000 || newBoostedAPY > 10000) revert STAKE_InvalidAPY();
        baseAPY = newBaseAPY;
        boostedAPY = newBoostedAPY;
        rewardRate = getCurrentAPY() * 1e18 / (365 days * 1e4);
        emit APYChanged(newBaseAPY, newBoostedAPY);
    }

    function boostAPY(uint256 duration) external permissioned updateReward(address(0)) {
        boostEndTime = block.timestamp + duration;
        rewardRate = getCurrentAPY() * 1e18 / (365 days * 100);
        emit APYBoosted(boostEndTime);
    }

    function setCooldownPeriod(uint256 newCooldown) external permissioned {
        if (newCooldown > 30 days) revert STAKE_InvalidCooldown();
        cooldownPeriod = newCooldown;
        emit CooldownSet(newCooldown);
    }

    function setEarlyUnstakeSlashRate(uint256 newSlashRate) external permissioned {
        if (newSlashRate > 5000) revert STAKE_InvalidSlashRate(); // Max 50% slash
        earlyUnstakeSlashRate = newSlashRate;
        emit EarlyUnstakeSlashSet(newSlashRate);
    }

    function setMaxStakeCap(uint256 newMaxStakeCap) external permissioned {
        maxStakeCap = newMaxStakeCap;
        emit MaxStakeCapSet(newMaxStakeCap);
    }

    function getStakeInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 pendingRewards,
        uint256 lastStakeTime,
        bool inCooldown
    ) {
        StakeInfo memory userStake = stakes[user];
        uint256 pendingReward = earned(user);
        return (
            userStake.amount,
            pendingReward,
            userStake.lastStakeTime,
            block.timestamp < userStake.lastStakeTime + cooldownPeriod
        );
    }

    function pause() external permissioned {
        _pause();
    }

    function unpause() external permissioned {
        _unpause();
    }
}
