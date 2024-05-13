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
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./utils/UUPSHelper.sol";

struct MerkleTree {
    // Root of a Merkle tree which leaves are `(address user, address token, uint amount)`
    // representing an amount of tokens accumulated by `user`.
    // The Merkle tree is assumed to have only increasing amounts: that is to say if a user can claim 1,
    // then after the amount associated in the Merkle tree for this token should be x > 1
    bytes32 merkleRoot;
    // Ipfs hash of the tree data
    bytes32 ipfsHash;
}

struct Claim {
    uint208 amount;
    uint48 timestamp;
    bytes32 merkleRoot;
}

/// @title Distributor
/// @notice Allows to claim rewards distributed to them through Merkl
/// @author Angle Labs. Inc
contract Distributor is UUPSHelper {
    using SafeERC20 for IERC20;

    /// @notice Epoch duration
    uint32 internal constant _EPOCH_DURATION = 3600;

    // ================================= VARIABLES =================================

    /// @notice Tree of claimable tokens through this contract
    MerkleTree public tree;

    /// @notice Tree that was in place in the contract before the last `tree` update
    MerkleTree public lastTree;

    /// @notice Token to deposit to freeze the roots update
    IERC20 public disputeToken;

    /// @notice `Core` contract handling access control
    ICore public core;

    /// @notice Address which created the dispute
    /// @dev Used to store if there is an ongoing dispute
    address public disputer;

    /// @notice When the current tree will become valid
    uint48 public endOfDisputePeriod;

    /// @notice Time after which a change in a tree becomes effective, in EPOCH_DURATION
    uint48 public disputePeriod;

    /// @notice Amount to deposit to freeze the roots update
    uint256 public disputeAmount;

    /// @notice Mapping user -> token -> amount to track claimed amounts
    mapping(address => mapping(address => Claim)) public claimed;

    /// @notice Trusted EOAs to update the Merkle root
    mapping(address => uint256) public canUpdateMerkleRoot;

    /// @notice Whether or not to disable permissionless claiming
    mapping(address => uint256) public onlyOperatorCanClaim;

    /// @notice user -> operator -> authorisation to claim
    mapping(address => mapping(address => uint256)) public operators;

    uint256[38] private __gap;

    // =================================== EVENTS ==================================

    event Claimed(address indexed user, address indexed token, uint256 amount);
    event DisputeAmountUpdated(uint256 _disputeAmount);
    event Disputed(string reason);
    event DisputePeriodUpdated(uint48 _disputePeriod);
    event DisputeResolved(bool valid);
    event DisputeTokenUpdated(address indexed _disputeToken);
    event OperatorClaimingToggled(address indexed user, bool isEnabled);
    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);
    event Recovered(address indexed token, address indexed to, uint256 amount);
    event Revoked(); // With this event an indexer could maintain a table (timestamp, merkleRootUpdate)
    event TreeUpdated(bytes32 merkleRoot, bytes32 ipfsHash, uint48 endOfDisputePeriod);
    event TrustedToggled(address indexed eoa, bool trust);

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!core.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernor() {
        if (!core.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` is the `user` address or is a trusted address
    modifier onlyTrustedOrUser(address user) {
        if (user != msg.sender && canUpdateMerkleRoot[msg.sender] != 1 && !core.isGovernorOrGuardian(msg.sender))
            revert NotTrusted();
        _;
    }

    // ================================ CONSTRUCTOR ================================

    constructor() initializer {}

    function initialize(ICore _core) external initializer {
        if (address(_core) == address(0)) revert ZeroAddress();
        core = _core;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyGovernorUpgrader(core) {}

    // =============================== MAIN FUNCTION ===============================

    /// @notice Claims rewards for a given set of users
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// who provides the proof and pays the gas: `msg.sender` is used only for addresses that require a trusted operator
    /// @param users Recipient of tokens
    /// @param tokens ERC20 claimed
    /// @param amounts Amount of tokens that will be sent to the corresponding users
    /// @param proofs Array of hashes bridging from a leaf `(hash of user | token | amount)` to the Merkle root
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        uint256 usersLength = users.length;
        if (
            usersLength == 0 ||
            usersLength != tokens.length ||
            usersLength != amounts.length ||
            usersLength != proofs.length
        ) revert InvalidLengths();

        for (uint256 i; i < usersLength; ) {
            address user = users[i];
            address token = tokens[i];
            uint256 amount = amounts[i];

            // Only approved operator can claim for `user`
            if (msg.sender != user && operators[user][msg.sender] == 0) revert NotWhitelisted();

            // Verifying proof
            bytes32 leaf = keccak256(abi.encode(user, token, amount));
            if (!_verifyProof(leaf, proofs[i])) revert InvalidProof();

            // Closing reentrancy gate here
            uint256 toSend = amount - claimed[user][token].amount;
            claimed[user][token] = Claim(SafeCast.toUint208(amount), uint48(block.timestamp), getMerkleRoot());

            IERC20(token).safeTransfer(user, toSend);
            emit Claimed(user, token, toSend);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the MerkleRoot that is currently live for the contract
    function getMerkleRoot() public view returns (bytes32) {
        if (block.timestamp >= endOfDisputePeriod && disputer == address(0)) return tree.merkleRoot;
        else return lastTree.merkleRoot;
    }

    // ============================ GOVERNANCE FUNCTIONS ===========================

    /// @notice Adds or removes EOAs which are trusted to update the Merkle root
    function toggleTrusted(address eoa) external onlyGovernor {
        uint256 trustedStatus = 1 - canUpdateMerkleRoot[eoa];
        canUpdateMerkleRoot[eoa] = trustedStatus;
        emit TrustedToggled(eoa, trustedStatus == 1);
    }

    /// @notice Updates Merkle Tree
    function updateTree(MerkleTree calldata _tree) external {
        if (
            disputer != address(0) ||
            // A trusted address cannot update a tree right after a precedent tree update otherwise it can de facto
            // validate a tree which has not passed the dispute period
            ((canUpdateMerkleRoot[msg.sender] != 1 || block.timestamp < endOfDisputePeriod) &&
                !core.isGovernor(msg.sender))
        ) revert NotTrusted();
        MerkleTree memory _lastTree = tree;
        tree = _tree;
        lastTree = _lastTree;

        uint48 _endOfPeriod = _endOfDisputePeriod(uint48(block.timestamp));
        endOfDisputePeriod = _endOfPeriod;
        emit TreeUpdated(_tree.merkleRoot, _tree.ipfsHash, _endOfPeriod);
    }

    /// @notice Freezes the Merkle tree update until the dispute is resolved
    /// @dev Requires a deposit of `disputeToken` that'll be slashed if the dispute is not accepted
    /// @dev It is only possible to create a dispute within `disputePeriod` after each tree update
    function disputeTree(string memory reason) external {
        if (disputer != address(0)) revert UnresolvedDispute();
        if (block.timestamp >= endOfDisputePeriod) revert InvalidDispute();
        IERC20(disputeToken).safeTransferFrom(msg.sender, address(this), disputeAmount);
        disputer = msg.sender;
        emit Disputed(reason);
    }

    /// @notice Resolve the ongoing dispute, if any
    /// @param valid Whether the dispute was valid
    function resolveDispute(bool valid) external onlyGovernor {
        if (disputer == address(0)) revert NoDispute();
        if (valid) {
            IERC20(disputeToken).safeTransfer(disputer, disputeAmount);
            // If a dispute is valid, the contract falls back to the last tree that was updated
            _revokeTree();
        } else {
            IERC20(disputeToken).safeTransfer(msg.sender, disputeAmount);
            endOfDisputePeriod = _endOfDisputePeriod(uint48(block.timestamp));
        }
        disputer = address(0);
        emit DisputeResolved(valid);
    }

    /// @notice Allows the governor or the guardian of this contract to fallback to the last version of the tree
    /// immediately
    function revokeTree() external onlyGovernor {
        if (disputer != address(0)) revert UnresolvedDispute();
        _revokeTree();
    }

    /// @notice Toggles permissioned claiming for a given user
    function toggleOnlyOperatorCanClaim(address user) external onlyTrustedOrUser(user) {
        uint256 oldValue = onlyOperatorCanClaim[user];
        onlyOperatorCanClaim[user] = 1 - oldValue;
        emit OperatorClaimingToggled(user, oldValue == 0);
    }

    /// @notice Toggles whitelisting for a given user and a given operator
    function toggleOperator(address user, address operator) external onlyTrustedOrUser(user) {
        uint256 oldValue = operators[user][operator];
        operators[user][operator] = 1 - oldValue;
        emit OperatorToggled(user, operator, oldValue == 0);
    }

    /// @notice Recovers any ERC20 token
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    /// @notice Sets the dispute period after which a tree update becomes effective
    function setDisputePeriod(uint48 _disputePeriod) external onlyGovernor {
        disputePeriod = uint48(_disputePeriod);
        emit DisputePeriodUpdated(_disputePeriod);
    }

    /// @notice Sets the token used as a caution during disputes
    function setDisputeToken(IERC20 _disputeToken) external onlyGovernor {
        if (disputer != address(0)) revert UnresolvedDispute();
        disputeToken = _disputeToken;
        emit DisputeTokenUpdated(address(_disputeToken));
    }

    /// @notice Sets the amount of `disputeToken` used as a caution during disputes
    function setDisputeAmount(uint256 _disputeAmount) external onlyGovernor {
        if (disputer != address(0)) revert UnresolvedDispute();
        disputeAmount = _disputeAmount;
        emit DisputeAmountUpdated(_disputeAmount);
    }

    // ============================= INTERNAL FUNCTIONS ============================

    /// @notice Fallback to the last version of the tree
    function _revokeTree() internal {
        MerkleTree memory _tree = lastTree;
        endOfDisputePeriod = 0;
        tree = _tree;
        emit Revoked();
        emit TreeUpdated(
            _tree.merkleRoot,
            _tree.ipfsHash,
            (uint48(block.timestamp) / _EPOCH_DURATION) * (_EPOCH_DURATION) // Last hour
        );
    }

    /// @notice Returns the end of the dispute period
    /// @dev treeUpdate is rounded up to next hour and then `disputePeriod` hours are added
    function _endOfDisputePeriod(uint48 treeUpdate) internal view returns (uint48) {
        return ((treeUpdate - 1) / _EPOCH_DURATION + 1 + disputePeriod) * (_EPOCH_DURATION);
    }

    /// @notice Checks the validity of a proof
    /// @param leaf Hashed leaf data, the starting point of the proof
    /// @param proof Array of hashes forming a hash chain from leaf to root
    /// @return true If proof is correct, else false
    function _verifyProof(bytes32 leaf, bytes32[] memory proof) internal view returns (bool) {
        bytes32 currentHash = leaf;
        uint256 proofLength = proof.length;
        for (uint256 i; i < proofLength; ) {
            if (currentHash < proof[i]) {
                currentHash = keccak256(abi.encode(currentHash, proof[i]));
            } else {
                currentHash = keccak256(abi.encode(proof[i], currentHash));
            }
            unchecked {
                ++i;
            }
        }
        bytes32 root = getMerkleRoot();
        if (root == bytes32(0)) revert InvalidUninitializedRoot();
        return currentHash == root;
    }
}
