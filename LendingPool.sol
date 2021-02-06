pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LendingPoolAddressesProvider } from "../interfaces/LendingPoolAddressesProvider.sol";

contract LendingPool {

    // Lending Providor contract
    // Acccess a specific lending pool via the provider
    LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(address(0x24a42fD28C976A61Df5D00D0599C34c4f90748c8)); // Mainnet Address
    LendingPool lendingPool = LendingPool(provider.getLendingPool());


}
