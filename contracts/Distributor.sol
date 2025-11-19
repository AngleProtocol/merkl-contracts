// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UUPSHelper } from "./utils/UUPSHelper.sol";
import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";
import { Errors } from "./utils/Errors.sol";
import { IClaimRecipient } from "./interfaces/IClaimRecipient.sol";

struct MerkleTree {
    /// @notice Root of a Merkle tree whose leaves are `(address user, address token, uint amount)`
    /// representing the cumulative amount of tokens earned by each user
    /// @dev The Merkle tree contains only monotonically increasing amounts: if a user previously claimed 1 token,
    /// subsequent tree updates should show amounts x > 1 for that user
    bytes32 merkleRoot;
    /// @dev Deprecated: this used to be the IPFS hash of the complete tree data
    bytes32 ipfsHash;
}

struct Claim {
    /// @notice Cumulative amount claimed by the user for this token
    uint208 amount;
    /// @notice Timestamp of the last claim
    uint48 timestamp;
    /// @notice Merkle root that was active when the last claim occurred
    bytes32 merkleRoot;
}

/// @title Distributor
/// @notice Manages the distribution of Merkl rewards and allows users to claim their earned tokens
/// @dev Implements a Merkle tree-based reward distribution system with dispute resolution mechanism
/// @author Merkl SAS
contract Distributor is UUPSHelper {
    using SafeERC20 for IERC20;

    /// @notice Default epoch duration in seconds (1 hour)
    uint32 internal constant _EPOCH_DURATION = 3600;

    /// @notice Success message that must be returned by `IClaimRecipient.onClaim` callback
    bytes32 public constant CALLBACK_SUCCESS = keccak256("IClaimRecipient.onClaim");

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Current active Merkle tree containing claimable token data
    MerkleTree public tree;

    /// @notice Previous Merkle tree that was active before the last update
    /// @dev Used to revert to if the current tree is disputed and found invalid
    MerkleTree public lastTree;

    /// @notice Token required as a deposit to dispute a tree update
    IERC20 public disputeToken;

    /// @notice Access control manager contract handling role-based permissions
    IAccessControlManager public accessControlManager;

    /// @notice Address that created the current ongoing dispute
    /// @dev Non-zero value indicates there is an active dispute
    address public disputer;

    /// @notice Timestamp after which the current tree becomes effective and undisputable
    uint48 public endOfDisputePeriod;

    /// @notice Number of epochs (in EPOCH_DURATION units) to wait before a tree update becomes effective
    uint48 public disputePeriod;

    /// @notice Amount of disputeToken required to create a dispute
    uint256 public disputeAmount;

    /// @notice Tracks cumulative claimed amounts for each user and token
    /// @dev Maps user => token => Claim details (amount, timestamp, merkleRoot)
    mapping(address => mapping(address => Claim)) public claimed;

    /// @notice Trusted addresses authorized to update the Merkle root
    /// @dev 1 = trusted, 0 = not trusted
    mapping(address => uint256) public canUpdateMerkleRoot;

    /// @notice Deprecated - kept for storage layout compatibility
    mapping(address => uint256) public onlyOperatorCanClaim;

    /// @notice Authorization for operators to claim on behalf of users
    /// @dev Maps user => operator => authorization status (1 = authorized, 0 = not authorized)
    mapping(address => mapping(address => uint256)) public operators;

    /// @notice Whether contract upgradeability has been permanently disabled
    /// @dev 1 = upgrades disabled, 0 = upgrades allowed
    uint128 public upgradeabilityDeactivated;

    /// @notice Reentrancy guard status
    /// @dev 1 = not entered, 2 = entered
    uint96 private _status;

    /// @notice Custom epoch duration for dispute periods in seconds
    /// @dev If 0, defaults to _EPOCH_DURATION
    uint32 internal _epochDuration;

    /// @notice Custom recipient addresses for user claims per token
    /// @dev Maps user => token => recipient address (zero address = use default behavior)
    /// @dev Setting recipient for address(0) token sets the default recipient for all tokens
    mapping(address => mapping(address => address)) public claimRecipient;

    /// @notice Global operators authorized to claim specific tokens on behalf of any user
    /// @dev Maps operator => token => authorization (1 = authorized, 0 = not authorized)
    /// @dev Authorization for address(0) token allows claiming any token for any user
    mapping(address => mapping(address => uint256)) public mainOperators;

    uint256[35] private __gap;

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
    event MainOperatorStatusUpdated(address indexed operator, address indexed token, bool isWhitelisted);
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

    /// @notice Restricts function access to addresses with governor role only
    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    /// @notice Restricts function access to addresses with governor or guardian role
    modifier onlyGuardian() {
        _onlyGuardian();
        _;
    }

    /// @notice Ensures the contract is still upgradeable and caller has governor role
    /// @dev Reverts if upgradeability has been revoked or caller is not a governor
    modifier onlyUpgradeableInstance() {
        if (upgradeabilityDeactivated == 1) revert Errors.NotUpgradeable();
        else if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /// @notice Prevents reentrancy attacks by locking the contract during execution
    /// @dev Uses a status flag that is set to 2 during execution and reset to 1 after
    modifier nonReentrant() {
        if (_status == 2) revert Errors.ReentrantCall();

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

    /// @notice Initializes the contract with access control manager
    /// @param _accessControlManager Address of the access control manager contract
    function initialize(IAccessControlManager _accessControlManager) external initializer {
        if (address(_accessControlManager) == address(0)) revert Errors.ZeroAddress();
        accessControlManager = _accessControlManager;
    }

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyUpgradeableInstance {}

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    MAIN FUNCTIONS                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Claims rewards for a set of users based on Merkle proofs
    /// @param users Addresses claiming rewards (or being claimed for)
    /// @param tokens ERC20 tokens being claimed
    /// @param amounts Cumulative amounts earned (not incremental amounts)
    /// @param proofs Merkle proofs validating each claim
    /// @dev Users can only claim for themselves unless they've authorized an operator
    /// @dev Arrays must all have the same length
    function claim(address[] calldata users, address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) external {
        address[] memory recipients = new address[](users.length);
        bytes[] memory datas = new bytes[](users.length);
        _claim(users, tokens, amounts, proofs, recipients, datas);
    }

    /// @notice Claims rewards with custom recipient addresses and callback data
    /// @param users Addresses claiming rewards (or being claimed for)
    /// @param tokens ERC20 tokens being claimed
    /// @param amounts Cumulative amounts earned (not incremental amounts)
    /// @param proofs Merkle proofs validating each claim
    /// @param recipients Custom recipient addresses for each claim (zero address = use default)
    /// @param datas Arbitrary data passed to recipient's onClaim callback (if recipient is a contract)
    /// @dev Only msg.sender claiming for themselves can override the recipient address
    /// @dev Non-zero recipient addresses override any previously set default recipients
    function claimWithRecipient(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] calldata recipients,
        bytes[] memory datas
    ) external {
        _claim(users, tokens, amounts, proofs, recipients, datas);
    }

    /// @notice Returns the currently active Merkle root for claim verification
    /// @return The Merkle root that is currently valid for claims
    /// @dev Returns lastTree.merkleRoot if within dispute period or if there's an active dispute
    /// @dev Returns tree.merkleRoot if dispute period has passed and no active dispute
    function getMerkleRoot() public view returns (bytes32) {
        if (block.timestamp >= endOfDisputePeriod && disputer == address(0)) return tree.merkleRoot;
        else return lastTree.merkleRoot;
    }

    /// @notice Returns the epoch duration used for dispute period calculations
    /// @return epochDuration The current epoch duration in seconds
    /// @dev Returns custom _epochDuration if set, otherwise returns default _EPOCH_DURATION (3600 seconds)
    function getEpochDuration() public view returns (uint32 epochDuration) {
        epochDuration = _epochDuration;
        if (epochDuration == 0) epochDuration = _EPOCH_DURATION;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 USER ADMIN FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Toggles an operator's authorization to claim rewards on behalf of a user
    /// @param user User granting or revoking the authorization
    /// @param operator Operator address being authorized or deauthorized
    /// @dev When operator is address(0), it enables any address to claim for the user
    /// @dev Only the user themselves or governance can toggle operator status
    function toggleOperator(address user, address operator) external {
        if (user != msg.sender && !accessControlManager.isGovernorOrGuardian(msg.sender)) revert Errors.NotTrusted();
        uint256 oldValue = operators[user][operator];
        operators[user][operator] = 1 - oldValue;
        emit OperatorToggled(user, operator, oldValue == 0);
    }

    /// @notice Sets a custom recipient address for a user's token claims
    /// @param recipient Address that will receive claimed tokens (zero address = default to user)
    /// @param token Token for which to set the recipient (zero address = all tokens)
    /// @dev Users can override this recipient when calling claimWithRecipient
    /// @dev Setting recipient to address(0) removes the custom recipient
    function setClaimRecipient(address recipient, address token) external {
        _setClaimRecipient(msg.sender, recipient, token);
    }

    /// @notice Toggles a main operator's authorization to claim tokens on behalf of any user
    /// @param operator Operator whose status is being toggled
    /// @param token Token for which authorization applies (zero address = all tokens)
    /// @dev Only callable by guardian for an individual token or governor if it's for all tokens
    /// @dev Main operators can claim for any user without individual user authorization
    function toggleMainOperatorStatus(address operator, address token) external {
        if (token == address(0)) _onlyGovernor();
        else _onlyGuardian();
        uint256 oldValue = mainOperators[operator][token];
        mainOperators[operator][token] = 1 - oldValue;
        emit MainOperatorStatusUpdated(operator, token, oldValue == 0);
    }

    /// @notice Creates a dispute to freeze the current Merkle tree update
    /// @param reason Explanation for why the tree update is being disputed
    /// @dev Requires depositing disputeAmount of disputeToken as collateral
    /// @dev Can only dispute within disputePeriod after a tree update
    /// @dev Deposit is slashed if dispute is rejected, returned if dispute is valid
    function disputeTree(string memory reason) external {
        if (disputer != address(0)) revert Errors.UnresolvedDispute();
        if (block.timestamp >= endOfDisputePeriod) revert Errors.InvalidDispute();
        IERC20(disputeToken).safeTransferFrom(msg.sender, address(this), disputeAmount);
        disputer = msg.sender;
        emit Disputed(reason);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                 GOVERNANCE FUNCTIONS                                               
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the active Merkle tree with new reward data
    /// @param _tree New Merkle tree containing updated reward information
    /// @dev Can only be called by trusted addresses or governor
    /// @dev Trusted addresses cannot update during an active dispute period to prevent circumventing disputes
    /// @dev Saves the current tree to lastTree before updating
    function updateTree(MerkleTree calldata _tree) external {
        if (
            disputer != address(0) ||
            // A trusted address cannot update a tree right after a precedent tree update otherwise it can de facto
            // validate a tree which has not passed the dispute period
            ((canUpdateMerkleRoot[msg.sender] != 1 || block.timestamp < endOfDisputePeriod) && !accessControlManager.isGovernor(msg.sender))
        ) revert Errors.NotTrusted();
        MerkleTree memory _lastTree = tree;
        tree = _tree;
        lastTree = _lastTree;

        uint48 _endOfPeriod = _endOfDisputePeriod(uint48(block.timestamp));
        endOfDisputePeriod = _endOfPeriod;
        emit TreeUpdated(_tree.merkleRoot, _tree.ipfsHash, _endOfPeriod);
    }

    /// @notice Toggles an address's authorization to update the Merkle tree
    /// @param trustAddress Address whose trusted status is being toggled
    /// @dev Only callable by governor
    /// @dev Trusted addresses can update trees but must wait for dispute periods
    function toggleTrusted(address trustAddress) external onlyGovernor {
        uint256 trustedStatus = 1 - canUpdateMerkleRoot[trustAddress];
        canUpdateMerkleRoot[trustAddress] = trustedStatus;
        emit TrustedToggled(trustAddress, trustedStatus == 1);
    }

    /// @notice Permanently disables contract upgradeability
    /// @dev Only callable by governor
    /// @dev This action is irreversible - use with extreme caution
    function revokeUpgradeability() external onlyGovernor {
        upgradeabilityDeactivated = 1;
        emit UpgradeabilityRevoked();
    }

    /// @notice Updates the epoch duration used for dispute period calculations
    /// @param epochDuration New epoch duration in seconds
    /// @dev Only callable by governor
    function setEpochDuration(uint32 epochDuration) external onlyGovernor {
        _epochDuration = epochDuration;
        emit EpochDurationUpdated(epochDuration);
    }

    /// @notice Resolves an ongoing dispute
    /// @param valid True if the dispute is valid (tree will be reverted), false if invalid (disputer loses deposit)
    /// @dev Only callable by governor
    /// @dev If valid: returns deposit to disputer and reverts to lastTree
    /// @dev If invalid: sends deposit to governor and extends dispute period
    function resolveDispute(bool valid) external onlyGovernor {
        if (disputer == address(0)) revert Errors.NoDispute();
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

    /// @notice Reverts to the previous Merkle tree immediately
    /// @dev Only callable by governor
    /// @dev Cannot be called if there's an active dispute (must resolve dispute first)
    function revokeTree() external onlyGovernor {
        if (disputer != address(0)) revert Errors.UnresolvedDispute();
        _revokeTree();
    }

    /// @notice Recovers ERC20 tokens accidentally sent to the contract
    /// @param tokenAddress Address of the token to recover
    /// @param to Address that will receive the recovered tokens
    /// @param amountToRecover Amount of tokens to recover
    /// @dev Only callable by governor
    function recoverERC20(address tokenAddress, address to, uint256 amountToRecover) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    /// @notice Updates the dispute period duration
    /// @param _disputePeriod New dispute period in epoch units
    /// @dev Only callable by governor
    function setDisputePeriod(uint48 _disputePeriod) external onlyGovernor {
        disputePeriod = uint48(_disputePeriod);
        emit DisputePeriodUpdated(_disputePeriod);
    }

    /// @notice Updates the token required as collateral for disputes
    /// @param _disputeToken New dispute token address
    /// @dev Only callable by governor
    /// @dev Cannot be changed during an active dispute
    function setDisputeToken(IERC20 _disputeToken) external onlyGovernor {
        if (disputer != address(0)) revert Errors.UnresolvedDispute();
        disputeToken = _disputeToken;
        emit DisputeTokenUpdated(address(_disputeToken));
    }

    /// @notice Updates the amount of tokens required to create a dispute
    /// @param _disputeAmount New dispute amount
    /// @dev Only callable by governor
    /// @dev Cannot be changed during an active dispute
    function setDisputeAmount(uint256 _disputeAmount) external onlyGovernor {
        if (disputer != address(0)) revert Errors.UnresolvedDispute();
        disputeAmount = _disputeAmount;
        emit DisputeAmountUpdated(_disputeAmount);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                   INTERNAL HELPERS                                                 
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal implementation of reward claiming with full recipient and callback support
    /// @param users Addresses claiming rewards
    /// @param tokens Tokens being claimed
    /// @param amounts Cumulative earned amounts (not incremental)
    /// @param proofs Merkle proofs for validation
    /// @param recipients Custom recipient addresses (zero = use default)
    /// @param datas Callback data for recipients
    /// @dev Validates authorization, verifies proofs, updates claimed amounts, and transfers tokens
    /// @dev Attempts to call onClaim callback on recipient if data is provided
    function _claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address[] memory recipients,
        bytes[] memory datas
    ) internal nonReentrant {
        uint256 usersLength = users.length;
        if (
            usersLength == 0 ||
            usersLength != tokens.length ||
            usersLength != amounts.length ||
            usersLength != proofs.length ||
            usersLength != recipients.length ||
            usersLength != datas.length
        ) revert Errors.InvalidLengths();

        for (uint256 i; i < usersLength; ) {
            address user = users[i];
            address token = tokens[i];
            uint256 amount = amounts[i];
            bytes memory data = datas[i];

            // Only approved operators can claim for `user`
            if (
                msg.sender != user &&
                tx.origin != user &&
                mainOperators[msg.sender][token] == 0 &&
                mainOperators[msg.sender][address(0)] == 0 &&
                operators[user][msg.sender] == 0 &&
                operators[user][address(0)] == 0 &&
                !accessControlManager.isGovernorOrGuardian(msg.sender)
            ) revert Errors.NotWhitelisted();

            // Verifying proof
            bytes32 leaf = keccak256(abi.encode(user, token, amount));
            if (!_verifyProof(leaf, proofs[i])) revert Errors.InvalidProof();

            // Closing reentrancy gate here
            uint256 toSend = amount - claimed[user][token].amount;
            claimed[user][token] = Claim(SafeCast.toUint208(amount), uint48(block.timestamp), getMerkleRoot());
            emit Claimed(user, token, toSend);

            address recipient = recipients[i];
            // Only `msg.sender` can set a different recipient for itself within the context of a call to claim
            // The recipient set in the context of the call to `claim` can override the default recipient set by the user
            if (msg.sender != user || recipient == address(0)) {
                address userSetRecipient = claimRecipient[user][token];
                if (userSetRecipient == address(0)) userSetRecipient = claimRecipient[user][address(0)];
                if (userSetRecipient == address(0)) recipient = user;
                else recipient = userSetRecipient;
            }

            if (toSend != 0) {
                IERC20(token).safeTransfer(recipient, toSend);
                if (data.length != 0) {
                    try IClaimRecipient(recipient).onClaim(user, token, amount, data) returns (bytes32 callbackSuccess) {
                        if (callbackSuccess != CALLBACK_SUCCESS) revert Errors.InvalidReturnMessage();
                    } catch {}
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Reverts to the previous Merkle tree
    /// @dev Resets endOfDisputePeriod to 0 and emits both Revoked and TreeUpdated events
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

    /// @notice Calculates when a tree update's dispute period ends
    /// @param treeUpdate Timestamp when the tree was updated
    /// @return Timestamp when the dispute period ends and tree becomes effective
    /// @dev Rounds treeUpdate up to next epoch boundary, then adds disputePeriod epochs
    function _endOfDisputePeriod(uint48 treeUpdate) internal view returns (uint48) {
        uint32 epochDuration = getEpochDuration();
        return ((treeUpdate - 1) / epochDuration + 1 + disputePeriod) * (epochDuration);
    }

    /// @notice Verifies a Merkle proof against the current active root
    /// @param leaf Hashed leaf data representing the claim (user, token, amount)
    /// @param proof Array of sibling hashes forming the path from leaf to root
    /// @return True if the proof is valid, false otherwise
    /// @dev Uses standard Merkle tree verification with sorted concatenation
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
        if (root == bytes32(0)) revert Errors.InvalidUninitializedRoot();
        return currentHash == root;
    }

    /// @notice Internal implementation for setting a claim recipient
    /// @param user User for whom to set the recipient
    /// @param recipient Address that will receive claimed tokens
    /// @param token Token for which recipient is set (address(0) = all tokens)
    function _setClaimRecipient(address user, address recipient, address token) internal {
        claimRecipient[user][token] = recipient;
        emit ClaimRecipientUpdated(user, recipient, token);
    }

    /// @notice Ensures the caller has governor role
    function _onlyGovernor() internal view {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
    }

    /// @notice Ensures the caller has guardian role
    function _onlyGuardian() internal view {
        if (!accessControlManager.isGovernorOrGuardian(msg.sender)) revert Errors.NotGovernorOrGuardian();
    }
}
