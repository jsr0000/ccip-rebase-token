// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @author  Josh Regnart
 * @title   CCIP Rebase Token
 * @dev     .
 * @notice  This is a cross chain rebase token that incentivizes users to deposit into a vault.
            The interest rate in the smart contract can only decrease. 
            Each user will have their own interest rate that is the global interest arte at the time of depositing.
 */

contract RebaseToken is ERC20 {

    error RebaseToken__interestRateCanOnlyDecrease();

    uint256 private s_interestRate = 5e18;
    
    constructor() ERC20("Rebase Token", "RBT") {}

    function setInterestRate(uint256 newInterestRate) external {
        if (newInterestRate < s_interestRate) {
            revert RebaseToken__interestRateCanOnlyDecrease(
                s_interestRate,
                newInterestRate
            );
        }
        s_interestRate = newInterestRate;
    }
}
