// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { DistributionCreator, CampaignParameters } from "../../DistributionCreator.sol";
import { Errors } from "../../utils/Errors.sol";

/// @title MerklGaugeMiddlemanTemplate
/// @notice Template for building a gauge system creating well-formated incentive campaigns on Merkl
/// @dev This is a template built for the case of a gauge which can be called through the function:
/// `notifyReward(address token, address gauge, uint256 amount)` with a transferFrom in it. Feel free
/// to reach out to us if your use case is different and you're looking to adapt this contract.
contract MerklGaugeMiddlemanTemplate is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Maps a (token,gauge) pair to its campaign parameters
    /// @dev Parameters for a campaign can be obtained easily from the Merkl creation frontend
    mapping(address => mapping(address => CampaignParameters)) public gaugeParams;

    /// @notice Merkl address to create campaigns
    /// @dev Can be left as null by default on most chains. This address is normally the same across the different
    /// chains on which Merkl is deployed, but there can be some exceptions
    address public distributionCreator;

    event GaugeParametersSet(address indexed token, address indexed gauge, CampaignParameters params);
    event DistributionCreatorSet(address indexed _distributionCreator);

    constructor(address _owner, address _distributionCreator) {
        transferOwnership(_owner);
        distributionCreator = _distributionCreator;
    }

    /// @notice Address of the Merkl contract managing rewards to be distributed
    function merklDistributionCreator() public view virtual returns (DistributionCreator _distributionCreator) {
        _distributionCreator = DistributionCreator(distributionCreator);
        if (address(_distributionCreator) == address(0)) return DistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
    }

    /// @notice Called by the gauge system to effectively create a campaign on `token` for `gauge`
    /// starting as of now with the parameters previously specified through the `setGaugeParameters` function
    /// @dev This function will do nothing if the reward distribution amount is too small with respect to the
    /// amount of tokens distributed
    /// @dev Requires an allowance to be given by the caller to this contract
    function notifyReward(address token, address gauge, uint256 amount) public {
        CampaignParameters memory params = gaugeParams[token][gauge];
        if (params.campaignData.length == 0) revert Errors.InvalidParams();
        DistributionCreator _distributionCreator = merklDistributionCreator();
        // Need to deal with Merkl minimum distribution amounts
        if (amount * 3600 > _distributionCreator.rewardTokenMinAmounts(token) * params.duration) {
            _handleAllowance(token, address(_distributionCreator), amount);
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            params.startTimestamp = uint32(block.timestamp);
            params.amount = amount;
            params.rewardToken = token;
            _distributionCreator.createCampaign(params);
        }
    }

    /// @notice Specifies the campaign parameters for the pair `token,gauge`
    /// @dev These parameters can be obtained from the Merkl campaign creation frontend
    function setGaugeParameters(address gauge, address token, CampaignParameters memory params) external onlyOwner {
        gaugeParams[token][gauge] = params;
        emit GaugeParametersSet(token, gauge, params);
    }

    /// @dev Infinite allowances on Merkl contracts are safe here (this contract never holds funds and Merkl is safe)
    function _handleAllowance(address token, address _distributionCreator, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), _distributionCreator);
        if (currentAllowance < amount) IERC20(token).safeIncreaseAllowance(_distributionCreator, type(uint256).max - currentAllowance);
    }

    /// @notice Recovers idle tokens left on the contract
    function recoverToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Updates the distributionCreator value if needed
    function setDistributionCreator(address _distributionCreator) external onlyOwner {
        distributionCreator = _distributionCreator;
        emit DistributionCreatorSet(_distributionCreator);
    }
}
