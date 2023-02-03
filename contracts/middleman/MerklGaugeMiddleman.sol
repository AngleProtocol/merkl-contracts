// SPDX-License-Identifier: GPL-3.0

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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../DistributionCreator.sol";

/// @title MerklGaugeMiddleman
/// @author Angle Labs, Inc.
/// @notice Manages the transfer of rewards from the `AngleDistributor` to the `DistributionCreator` contract
/// @dev This contract is built under the assumption that the `DistributionCreator` contract has already whitelisted
/// this contract for it to distribute rewards without having to sign a message
/// @dev It also assumes that only `ANGLE` rewards will be sent from the `AngleDistributor`
contract MerklGaugeMiddleman {
    using SafeERC20 for IERC20;

    // ================================= PARAMETERS ================================

    /// @notice `CoreBorrow` contract handling access control
    ICoreBorrow public coreBorrow;

    /// @notice Maps a gauge to its reward parameters
    mapping(address => DistributionParameters) public gaugeParams;

    // =================================== EVENT ===================================

    event GaugeSet(address indexed gauge);

    constructor(ICoreBorrow _coreBorrow) {
        if (address(_coreBorrow) == address(0)) revert ZeroAddress();
        coreBorrow = _coreBorrow;
        IERC20 _angle = angle();
        // Condition left here for testing purposes
        if (address(_angle) != address(0))
            _angle.safeIncreaseAllowance(address(merkleRewardManager()), type(uint256).max);
    }

    // ================================= REFERENCES ================================

    /// @notice Address of the `AngleDistributor` contract
    function angleDistributor() public view virtual returns (address) {
        return 0x4f91F01cE8ec07c9B1f6a82c18811848254917Ab;
    }

    /// @notice Address of the ANGLE token
    function angle() public view virtual returns (IERC20) {
        return IERC20(0x31429d1856aD1377A8A0079410B297e1a9e214c2);
    }

    /// @notice Address of the Merkl contract managing rewards to be distributed
    // TODO: to be replaced at deployment
    function merkleRewardManager() public view virtual returns (DistributionCreator) {
        return DistributionCreator(0x4f91F01cE8ec07c9B1f6a82c18811848254917Ab);
    }

    // ============================= EXTERNAL FUNCTIONS ============================

    /// @notice Restores the allowance for the ANGLE token to the `DistributionCreator` contract
    function setAngleAllowance() external {
        IERC20 _angle = angle();
        address manager = address(merkleRewardManager());
        uint256 currentAllowance = _angle.allowance(address(this), manager);
        if (currentAllowance < type(uint256).max)
            _angle.safeIncreaseAllowance(manager, type(uint256).max - currentAllowance);
    }

    /// @notice Specifies the reward distribution parameters for `gauge`
    function setGauge(address gauge, DistributionParameters memory params) external {
        if (!coreBorrow.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        DistributionCreator manager = merkleRewardManager();
        if (
            gauge == address(0) ||
            params.rewardToken != address(angle()) ||
            (manager.isWhitelistedToken(IUniswapV3Pool(params.uniV3Pool).token0()) == 0 &&
                manager.isWhitelistedToken(IUniswapV3Pool(params.uniV3Pool).token0()) == 0)
        ) revert InvalidParams();
        gaugeParams[gauge] = params;
        emit GaugeSet(gauge);
    }

    /// @notice Transmits rewards from the `AngleDistributor` to the `DistributionCreator` with the correct
    /// parameters
    /// @dev Only callable by the `AngleDistributor` contract
    function notifyReward(address gauge, uint256 amount) external {
        DistributionParameters memory params = gaugeParams[gauge];
        if (msg.sender != angleDistributor() || params.uniV3Pool == address(0)) revert InvalidParams();
        params.epochStart = uint32(block.timestamp);
        params.amount = amount;
        merkleRewardManager().createDistribution(params);
    }
}
