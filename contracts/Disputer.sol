// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Distributor } from "./Distributor.sol";
import { Errors } from "./utils/Errors.sol";

contract Disputer is Ownable {
    Distributor public distributor;
    mapping(address => bool) public whitelist;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `msg.sender` is a whitelisted address
    modifier onlyWhitelisted() {
        if (!whitelist[msg.sender]) revert Errors.NotWhitelisted();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(address _owner, address[] memory _initialWhitelist, Distributor _distributor) {
        distributor = _distributor;

        // Set infinite approval for the distributor
        IERC20(_distributor.disputeToken()).approve(address(_distributor), type(uint256).max);
        uint256 length = _initialWhitelist.length;
        for (uint256 i; i < length; ) {
            whitelist[_initialWhitelist[i]] = true;
            unchecked {
                ++i;
            }
        }
        transferOwnership(_owner);
    }

    /// @notice Toggles a dispute for the given `reason`
    /// @dev Only whitelisted addresses can dispute
    /// @param reason Reason for the dispute
    function toggleDispute(string memory reason) external onlyWhitelisted {
        address disputeToken = address(distributor.disputeToken());
        uint256 disputeAmount = distributor.disputeAmount();

        uint256 contractBalance = IERC20(disputeToken).balanceOf(address(this));
        if (contractBalance < disputeAmount) {
            // Transfer funds from msg.sender if needed
            if (!IERC20(disputeToken).transferFrom(msg.sender, address(this), disputeAmount - contractBalance)) {
                revert Errors.DisputeFundsTransferFailed();
            }
        }

        // Attempt to dispute
        distributor.disputeTree(reason);
    }

    /// @notice Withdraws a given amount of a token
    /// @dev Only the owner can withdraw the funds
    /// @param asset Asset to withdraw
    /// @param to Receiver of the funds
    /// @param amount Amount to withdraw
    function withdrawFunds(address asset, address to, uint256 amount) external onlyOwner {
        IERC20(asset).transfer(to, amount);
    }

    /// @notice Withdraws a given amount of ETH
    /// @dev Only the owner can withdraw ETH
    /// @param to Receiver of the funds (payable address)
    /// @param amount Amount to withdraw
    function withdrawFunds(address payable to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{ value: amount }("");
        if (!success) revert Errors.WithdrawalFailed();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   SETTERS FUNCTIONS                                                
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Adds an address to the whitelist
    /// @dev Only the owner can add addresses to the whitelist
    /// @param _address Address to add to the whitelist
    function addToWhitelist(address _address) external onlyOwner {
        whitelist[_address] = true;
    }

    /// @notice Removes an address from the whitelist
    /// @dev Only the owner can remove addresses from the whitelist
    /// @param _address Address to remove from the whitelist
    function removeFromWhitelist(address _address) external onlyOwner {
        whitelist[_address] = false;
    }

    /// @notice Sets the distributor
    /// @dev Only the owner can set the distributor
    /// @param _distributor Distributor to set
    function setDistributor(Distributor _distributor) external onlyOwner {
        // Remove approval from old distributor
        IERC20(distributor.disputeToken()).approve(address(distributor), 0);
        distributor = _distributor;
        // Set infinite approval for new distributor
        IERC20(_distributor.disputeToken()).approve(address(_distributor), type(uint256).max);
    }
}
