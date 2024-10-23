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

interface IClaimRecipient {
    /// @notice Hook to call within contracts receiving token rewards on behalf of users
    function onClaim(address user, address token, uint256 amount, bytes memory data) external returns (bytes32);
}

/// @title Distributor
/// @notice Allows to claim rewards distributed to them through Merkl
/// @author Angle Labs. Inc
contract Distributor is UUPSHelper {
    using SafeERC20 for IERC20;

    /// @notice Default epoch duration
    uint32 internal constant _EPOCH_DURATION = 3600;

    /// @notice Success message received when calling a `ClaimRecipient` contract
    bytes32 public constant CALLBACK_SUCCESS = keccak256("IClaimRecipient.onClaim");

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Tree of claimable tokens through this contract
    MerkleTree public tree;

    /// @notice Tree that was in place in the contract before the last `tree` update
    MerkleTree public lastTree;

    /// @notice Token to deposit to freeze the roots update
    IERC20 public disputeToken;

    /// @notice Contract handling access control
    IAccessControlManager public core;

    /// @notice Address which created the last dispute
    /// @dev Used to store if there is an ongoing dispute
    address public disputer;

    /// @notice When the current tree becomes valid
    uint48 public endOfDisputePeriod;

    /// @notice Time after which a change in a tree becomes effective, in EPOCH_DURATION
    uint48 public disputePeriod;

    /// @notice Amount to deposit to freeze the roots update
    uint256 public disputeAmount;

    /// @notice Mapping user -> token -> amount to track claimed amounts
    mapping(address => mapping(address => Claim)) public claimed;

    /// @notice Trusted EOAs to update the Merkle root
    mapping(address => uint256) public canUpdateMerkleRoot;

    /// @notice Deprecated mapping
    mapping(address => uint256) public onlyOperatorCanClaim;

    /// @notice User -> Operator -> authorisation to claim on behalf of the user
    mapping(address => mapping(address => uint256)) public operators;

    /// @notice Whether the contract has been made non upgradeable or not
    uint128 public upgradeabilityDeactivated;

    /// @notice Reentrancy status
    uint96 private _status;

    /// @notice Epoch duration for dispute periods (in seconds)
    uint32 internal _epochDuration;

    /// @notice user -> token -> recipient address for when user claims `token`
    /// @dev If the mapping is empty, by default rewards will accrue on the user address
    mapping(address => mapping(address => address)) public claimRecipient;

    uint256[36] private __gap;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    event Claimed(address indexed user, address indexed token, uint256 amount);
    event ClaimRecipientUpdated(address indexed user, address indexed token, address indexed recipient);
    event DisputeAmountUpdated(uint256 _disputeAmount);
    event Disputed(string reason);
    event DisputePeriodUpdated(uint48 _disputePeriod);
    event DisputeResolved(bool valid);
    event DisputeTokenUpdated(address indexed _disputeToken);
    event EpochDurationUpdated(uint32 newEpochDuration);
    event OperatorClaimingToggled(address indexed user, bool isEnabled);
    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);
    event Recovered(address indexed token, address indexed to, uint256 amount);
    event Revoked(); // With this event an indexer could maintain a table (timestamp, merkleRootUpdate)
    event TreeUpdated(bytes32 merkleRoot, bytes32 ipfsHash, uint48 endOfDisputePeriod);
    event TrustedToggled(address indexed eoa, bool trust);
    event UpgradeabilityRevoked();

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `msg.sender` has the governor role
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

    /// @notice Checks whether the contract is upgradeable or whether the caller is allowed to upgrade the contract
    modifier onlyUpgradeableInstance() {
        if (upgradeabilityDeactivated == 1) revert NotUpgradeable();
        else if (!core.isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether a call is reentrant or not
    modifier nonReentrant() {
        if (_status == 2) revert ReentrantCall();

        // Any calls to nonReentrant after this point will fail
        _status = 2;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = 1;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor() initializer {}

    function initialize(IAccessControlManager _core) external initializer {
        if (address(_core) == address(0)) revert ZeroAddress();
        core = _core;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override onlyUpgradeableInstance {}

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    MAIN FUNCTIONS                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Claims rewards for a given set of users
    /// @dev Unless another address has been approved for claiming, only an address can claim for itself
    /// @param users Addresses for which claiming is taking place
    /// @param tokens ERC20 token claimed
    /// @param amounts Amount of tokens that will be sent to the corresponding users
    /// @param proofs Array of hashes bridging from a leaf `(hash of user | token | amount)` to the Merkle root
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        bytes memory data;
        address[] memory recipients = new address[](users.length);
        _claim(users, tokens, amounts, proofs, recipients, data);
    }

    /// @notice Same as the function above except that for each token claimed, the caller may set different
    /// recipients for rewards and pass arbitrary data to the reward recipient on claim
    /// @dev Only a `msg.sender` calling for itself can set a different recipient for the token rewards
    /// within the context of a call to claim
    /// @dev Non-zero recipient addresses given by the `msg.sender` can override any previously set reward address
    function claimWithRecipient(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] calldata recipients,
        bytes memory data
    ) external {
        _claim(users, tokens, amounts, proofs, recipients, data);
    }

    /// @notice Returns the Merkle root that is currently live for the contract
    function getMerkleRoot() public view returns (bytes32) {
        if (block.timestamp >= endOfDisputePeriod && disputer == address(0)) return tree.merkleRoot;
        else return lastTree.merkleRoot;
    }

    function getEpochDuration() public view returns (uint32 epochDuration) {
        epochDuration = _epochDuration;
        if (epochDuration == 0) epochDuration = _EPOCH_DURATION;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 USER ADMIN FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Toggles whitelisting for a given user and a given operator
    /// @dev When an operator is whitelisted for a user, the operator can claim rewards on behalf of the user
    function toggleOperator(address user, address operator) external onlyTrustedOrUser(user) {
        uint256 oldValue = operators[user][operator];
        operators[user][operator] = 1 - oldValue;
        emit OperatorToggled(user, operator, oldValue == 0);
    }

    /// @notice Sets a recipient for a user claiming rewards for a token
    /// @dev This is an optional functionality and if the `recipient` is set to the zero address, then
    /// the user will still accrue all rewards to its address
    /// @dev Users may still specify a different recipient when they claim token rewards with the
    /// `claimWithRecipient` function
    function setClaimRecipient(address recipient, address token) external {
        claimRecipient[msg.sender][token] = recipient;
        emit ClaimRecipientUpdated(msg.sender, recipient, token);
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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GOVERNANCE FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the Merkle tree
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

    /// @notice Adds or removes EOAs which are trusted to update the Merkle root
    function toggleTrusted(address eoa) external onlyGovernor {
        uint256 trustedStatus = 1 - canUpdateMerkleRoot[eoa];
        canUpdateMerkleRoot[eoa] = trustedStatus;
        emit TrustedToggled(eoa, trustedStatus == 1);
    }

    /// @notice Prevents future contract upgrades
    function revokeUpgradeability() external onlyGovernor {
        upgradeabilityDeactivated = 1;
        emit UpgradeabilityRevoked();
    }

    /// @notice Updates the epoch duration period
    function setEpochDuration(uint32 epochDuration) external onlyGovernor {
        _epochDuration = epochDuration;
        emit EpochDurationUpdated(epochDuration);
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

    /// @notice Allows the governor of this contract to fallback to the last version of the tree
    /// immediately
    function revokeTree() external onlyGovernor {
        if (disputer != address(0)) revert UnresolvedDispute();
        _revokeTree();
    }

    /// @notice Recovers any ERC20 token left on the contract
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

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   INTERNAL HELPERS                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal version of `claimWithRecipient`
    function _claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] memory recipients,
        bytes memory data
    ) internal nonReentrant {
        uint256 usersLength = users.length;
        if (
            usersLength == 0 ||
            usersLength != tokens.length ||
            usersLength != amounts.length ||
            usersLength != proofs.length ||
            usersLength != recipients.length
        ) revert InvalidLengths();

        for (uint256 i; i < usersLength; ) {
            address user = users[i];
            address token = tokens[i];
            uint256 amount = amounts[i];

            // Only approved operator can claim for `user`
            if (msg.sender != user && tx.origin != user && operators[user][msg.sender] == 0) revert NotWhitelisted();

            // Verifying proof
            bytes32 leaf = keccak256(abi.encode(user, token, amount));
            if (!_verifyProof(leaf, proofs[i])) revert InvalidProof();

            // Closing reentrancy gate here
            uint256 toSend = amount - claimed[user][token].amount;
            claimed[user][token] = Claim(SafeCast.toUint208(amount), uint48(block.timestamp), getMerkleRoot());
            emit Claimed(user, token, toSend);

            address recipient = recipients[i];
            // Only `msg.sender` can set a different recipient for itself within the context of a call to claim
            // The recipient set in the context of the call to `claim` can override the default recipient set by the user
            if (msg.sender != user || recipient == address(0)) {
                address userSetRecipient = claimRecipient[user][token];
                if (userSetRecipient == address(0)) recipient = user;
                else recipient = userSetRecipient;
            }

            if (toSend != 0) {
                IERC20(token).safeTransfer(recipient, toSend);
                if (data.length != 0) {
                    try IClaimRecipient(recipient).onClaim(user, token, amount, data) returns (
                        bytes32 callbackSuccess
                    ) {
                        if (callbackSuccess != CALLBACK_SUCCESS) revert InvalidReturnMessage();
                    } catch {}
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Fallback to the last version of the tree
    function _revokeTree() internal {
        MerkleTree memory _tree = lastTree;
        endOfDisputePeriod = 0;
        tree = _tree;
        uint32 epochDuration = getEpochDuration();
        emit Revoked();
        emit TreeUpdated(
            _tree.merkleRoot,
            _tree.ipfsHash,
            (uint48(block.timestamp) / epochDuration) * (epochDuration) // Last hour
        );
    }

    /// @notice Returns the end of the dispute period
    /// @dev treeUpdate is rounded up to next hour and then `disputePeriod` hours are added
    function _endOfDisputePeriod(uint48 treeUpdate) internal view returns (uint48) {
        uint32 epochDuration = getEpochDuration();
        return ((treeUpdate - 1) / epochDuration + 1 + disputePeriod) * (epochDuration);
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
