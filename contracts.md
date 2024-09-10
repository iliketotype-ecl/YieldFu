1. Base Contracts:

   - DebasingTokenBase.sol: Implements ERC20 with debasing functionality
   - StakingBase.sol: Manages staking logic and state
   - BondingBase.sol: Handles bonding mechanics and state

2. Controller Contract:

   - Controller.sol: Mediates between policies and base contracts, implements core business logic

3. Policy Contracts:

   - TokenPolicy.sol: User-facing contract for token operations (mint, burn, debase)
   - StakingPolicy.sol: User-facing contract for staking operations
   - BondingPolicy.sol: User-facing contract for bonding operations

4. Interface Contracts:

   - IDebasingTokenBase.sol: Defines interface for DebasingTokenBase
   - IStakingBase.sol: Defines interface for StakingBase
   - IBondingBase.sol: Defines interface for BondingBase
   - IController.sol: Defines interface for Controller

5. Test Files:
   - Each .test.js file corresponds to a contract, testing its specific functionality
   - FullSystem.test.js in the integration directory tests the entire system working together
