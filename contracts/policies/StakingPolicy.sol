// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "../Kernel.sol";
import "../modules/STAKE.sol";
import "../modules/MINTR.sol";

contract StakingPolicy is Policy {
    STAKE public staking;
    MINTR public mintr;

    constructor(Kernel kernel_) Policy(kernel_) {
        staking = STAKE(getModuleAddress(toKeycode("STAKE")));
        mintr = MINTR(getModuleAddress(toKeycode("MINTR")));
    }

    // Declare dependencies on the STAKE and MINTR modules
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);   
        dependencies[0] = toKeycode("STAKE");
        dependencies[1] = toKeycode("MINTR");
    }

    // Request permissions for interacting with the STAKE and MINTR modules
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](5);
        requests[0] = Permissions(toKeycode("STAKE"), staking.stake.selector);
        requests[1] = Permissions(toKeycode("STAKE"), staking.unstake.selector);
        requests[2] = Permissions(toKeycode("STAKE"), staking.getReward.selector);
        requests[3] = Permissions(toKeycode("MINTR"), mintr.mint.selector);
        requests[4] = Permissions(toKeycode("STAKE"), staking.boostAPY.selector);
    }

    // Stake tokens on behalf of the user
    function stake(uint256 amount) external {
        staking.stake(msg.sender, amount);  // Passing user's address
    }

    // Unstake tokens on behalf of the user
    function unstake(uint256 amount) external {
        staking.unstake(msg.sender, amount);  // Passing user's address
    }

    // Claim the rewards earned by the user
    function claimReward() external {
        staking.getReward();  // Let the STAKE module handle the rewards
    }


    // Boost the APY for a certain duration (this might require permissioning)
    function boostAPY(uint256 duration) external {
        staking.boostAPY(duration);  // You might want to add permission checks here
    }

    event RewardClaimed(address indexed user, uint256 reward);
}
