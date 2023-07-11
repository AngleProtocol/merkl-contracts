// SPDX-License-Identifier: BUSL-1.1

/*
                  *                                                  █                              
                *****                                               ▓▓▓                             
                  *                                               ▓▓▓▓▓▓▓                         
                                   *            ///.           ▓▓▓▓▓▓▓▓▓▓▓▓▓                       
                                 *****        ////////            ▓▓▓▓▓▓▓                          
                                   *       /////////////            ▓▓▓                             
                     ▓▓                  //////////////////          █         ▓▓                   
                   ▓▓  ▓▓             ///////////////////////                ▓▓   ▓▓                
                ▓▓       ▓▓        ////////////////////////////           ▓▓        ▓▓              
              ▓▓            ▓▓    /////////▓▓▓///////▓▓▓/////////       ▓▓             ▓▓            
           ▓▓                 ,////////////////////////////////////// ▓▓                 ▓▓         
        ▓▓                  //////////////////////////////////////////                     ▓▓      
      ▓▓                  //////////////////////▓▓▓▓/////////////////////                          
                       ,////////////////////////////////////////////////////                        
                    .//////////////////////////////////////////////////////////                     
                     .//////////////////////////██.,//////////////////////////█                     
                       .//////////////////////████..,./////////////////////██                       
                        ...////////////////███████.....,.////////////////███                        
                          ,.,////////////████████ ........,///////////████                          
                            .,.,//////█████████      ,.......///////████                            
                               ,..//████████           ........./████                               
                                 ..,██████                .....,███                                 
                                    .██                     ,.,█                                    
                                                                                                    
                                                                                                    
                                                                                                    
               ▓▓            ▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓        ▓▓               ▓▓▓▓▓▓▓▓▓▓          
             ▓▓▓▓▓▓          ▓▓▓    ▓▓▓       ▓▓▓               ▓▓               ▓▓   ▓▓▓▓         
           ▓▓▓    ▓▓▓        ▓▓▓    ▓▓▓       ▓▓▓    ▓▓▓        ▓▓               ▓▓▓▓▓             
          ▓▓▓        ▓▓      ▓▓▓    ▓▓▓       ▓▓▓▓▓▓▓▓▓▓        ▓▓▓▓▓▓▓▓▓▓       ▓▓▓▓▓▓▓▓▓▓          
*/

pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../DistributionCreator.sol";

/// @title MerklGaugeMiddleman
/// @author Angle Labs, Inc.
/// @notice Manages the transfer of ANGLE rewards to the `DistributionCreator` contract
/// @dev This contract is built under the assumption that the `DistributionCreator` contract has already whitelisted
/// this contract for it to distribute rewards without having to sign a message
/// @dev Transient funds left in this contract after a call may be exploited
contract MerklGaugeMiddleman {
    using SafeERC20 for IERC20;

    // ================================= PARAMETERS ================================

    /// @notice Contract handling access control
    ICore public accessControlManager;

    /// @notice Maps a gauge to its reward parameters
    mapping(address => DistributionParameters) public gaugeParams;

    // =================================== EVENT ===================================

    event GaugeSet(address indexed gauge);

    constructor(ICore _accessControlManager) {
        if (address(_accessControlManager) == address(0)) revert ZeroAddress();
        accessControlManager = _accessControlManager;
        IERC20 _angle = angle();
        // Condition left here for testing purposes
        if (address(_angle) != address(0))
            _angle.safeIncreaseAllowance(address(merklDistributionCreator()), type(uint256).max);
    }

    // ================================= REFERENCES ================================

    /// @notice Address of the ANGLE token
    function angle() public view virtual returns (IERC20) {
        return IERC20(0x31429d1856aD1377A8A0079410B297e1a9e214c2);
    }

    /// @notice Address of the Merkl contract managing rewards to be distributed
    /// @dev Address is the same across the different chains on which it is deployed
    function merklDistributionCreator() public view virtual returns (DistributionCreator) {
        return DistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd);
    }

    // ============================= EXTERNAL FUNCTIONS ============================

    /// @notice Restores the allowance for the ANGLE token to the `DistributionCreator` contract
    function setAngleAllowance() external {
        IERC20 _angle = angle();
        address manager = address(merklDistributionCreator());
        uint256 currentAllowance = _angle.allowance(address(this), manager);
        if (currentAllowance < type(uint256).max)
            _angle.safeIncreaseAllowance(manager, type(uint256).max - currentAllowance);
    }

    /// @notice Specifies the reward distribution parameters for `gauge`
    function setGauge(address gauge, DistributionParameters memory params) external {
        if (!accessControlManager.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        DistributionCreator manager = merklDistributionCreator();
        if (
            gauge == address(0) ||
            params.rewardToken != address(angle()) ||
            (manager.isWhitelistedToken(IUniswapV3Pool(params.uniV3Pool).token0()) == 0 &&
                manager.isWhitelistedToken(IUniswapV3Pool(params.uniV3Pool).token1()) == 0)
        ) revert InvalidParams();
        gaugeParams[gauge] = params;
        emit GaugeSet(gauge);
    }

    /// @notice Transmits rewards from the `AngleDistributor` to the `DistributionCreator` with the correct
    /// parameters
    /// @dev Callable by any contract
    /// @dev This method can be used to recover leftover ANGLE tokens in the contract
    function notifyReward(address gauge, uint256 amount) public {
        DistributionParameters memory params = gaugeParams[gauge];
        if (params.uniV3Pool == address(0)) revert InvalidParams();
        if (amount == 0) amount = angle().balanceOf(address(this));
        params.epochStart = uint32(block.timestamp);
        params.amount = amount;
        DistributionCreator creator = merklDistributionCreator();
        if (amount > 0) {
            // Need to deal with minimum distribution amounts
            if (amount > creator.rewardTokenMinAmounts(address(angle())) * params.numEpoch) {
                merklDistributionCreator().createDistribution(params);
            } else {
                // Sending leftover ANGLE tokens to the `msg.sender`
                angle().safeTransfer(msg.sender, amount);
            }
        }
    }

    /// @notice Fetches tokens and transmits rewards in the same transaction
    function notifyRewardWithTransfer(address gauge, uint256 amount) external {
        angle().safeTransferFrom(msg.sender, address(this), amount);
        notifyReward(gauge, amount);
    }
}
