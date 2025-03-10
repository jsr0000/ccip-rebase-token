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
    error RebaseToken__interestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    uint256 private s_interestRate = 5e18;
    uint256 private constant PRECISION_FACTOR = 1e18;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_usersLastUpdatedTimeStamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    function setInterestRate(uint256 newInterestRate) external {
        if (newInterestRate < s_interestRate) {
            revert RebaseToken__interestRateCanOnlyDecrease(
                s_interestRate,
                newInterestRate
            );
        }
        s_interestRate = newInterestRate;
        emit InterestRateSet(newInterestRate);
    }

    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    function balanceOf(address _user) public view override returns (uint256) {
        return
            (super.balanceOf(_user) *
                _calculatedUserAccumulatedInterestSinceLastUpdate(_user)) /
            PRECISION_FACTOR;
    }

    function _calculatedUserAccumulatedInterestSinceLastUpdate(
        address _user
    ) internal view returns (uint256 linnearInterest) {
        uint256 timeElapsed = block.timestamp -
            s_usersLastUpdatedTimeStamp[_user];
        linnearInterest =
            PRECISION_FACTOR +
            (s_userInterestRate[_user] * timeElapsed);
    }

    function _mintAccruedInterest(address _user) internal {
        s_usersLastUpdatedTimeStamp[_user] = block.timestamp;
    }

    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userInterestRate[user];
    }
}
