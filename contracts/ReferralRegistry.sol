// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { UUPSHelper } from "./utils/UUPSHelper.sol";
import { IAccessControlManager } from "./interfaces/IAccessControlManager.sol";
import { Errors } from "./utils/Errors.sol";

/// @title ReferralRegistry
/// @notice Allows to manage referral programs and claim rewards distributed through Merkl
/// @dev This contract uses UUPS upgradeability pattern and ReentrancyGuard for security
contract ReferralRegistry is UUPSHelper {
    using SafeERC20 for IERC20;
    struct ReferralProgram {
        address owner;
        bool requiresAuthorization;
        bool requiresRefererToBeSet;
        uint256 cost;
        address paymentToken;
    }
    enum ReferralStatus {
        NotAllowed,
        Allowed,
        Set
    }

    /// @notice Address to receive fees
    address public feeRecipient;

    /// @notice `AccessControlManager` contract handling access control
    IAccessControlManager public accessControlManager;

    /// @notice Whether the contract has been made non upgradeable or not
    uint128 public upgradeabilityDeactivated;

    /// @notice Cost to create a referral program
    uint256 public costReferralProgram;

    /// @notice List of string keys that are currently in a referral program
    string[] public referralKeys;

    /// @notice Mapping to store referral program details
    mapping(string => ReferralProgram) public referralPrograms;

    /// @notice Mapping to determine if a user is allowed to be a referrer
    mapping(string => mapping(address => ReferralStatus)) public refererStatus;

    /// @notice Mapping to store referrer codes
    mapping(string => mapping(address => string)) public referrerCodeMapping;

    /// @notice Mapping to store referrer addresses by code
    mapping(string => mapping(string => address)) public codeToReferrer;

    /// @notice Mapping to store user to referrer relationships
    mapping(string => mapping(address => address)) public keyToUserToReferrer;

    /// @notice Mapping to list referred
    mapping(string => mapping(address => address[])) public keyToReferred;

    /// @notice Adds a new referral key to the list
    /// @param key The referral key to add
    /// @param _cost The cost of the referral program
    /// @param _requiresRefererToBeSet Whether the referral program requires a referrer to be set
    /// @param _owner The owner of the referral program
    /// @param _requiresAuthorization Whether the referral program requires authorization
    /// @param _paymentToken The token used for payment in the referral program
    function addReferralKey(
        string calldata key,
        uint256 _cost,
        bool _requiresRefererToBeSet,
        address _owner,
        bool _requiresAuthorization,
        address _paymentToken
    ) external payable {
        if (referralPrograms[key].owner != address(0)) revert Errors.KeyAlreadyUsed();
        if (msg.value < costReferralProgram) revert Errors.NotEnoughPayment();
        if (_cost != 0 && !_requiresRefererToBeSet) revert Errors.InvalidParam();
        referralKeys.push(key);
        referralPrograms[key] = ReferralProgram({
            owner: _owner,
            requiresAuthorization: _requiresAuthorization,
            cost: _cost,
            requiresRefererToBeSet: _requiresRefererToBeSet,
            paymentToken: _paymentToken
        });
        if (costReferralProgram > 0) {
            (bool sent, ) = feeRecipient.call{ value: msg.value }("");
            if (!sent) revert Errors.NotEnoughPayment();
        }
        emit ReferralKeyAdded(key, referralPrograms[key]);
    }

    /// @notice Edits the parameters of a referral program
    /// @param key The referral key to edit
    /// @param newCost The new cost of the referral program
    /// @param newRequiresAuthorization Whether the referral program requires authorization
    /// @param newRequiresRefererToBeSet Whether the referral program requires a referrer to be set
    /// @param newPaymentToken The new payment token of the referral program
    function editReferralProgram(
        string calldata key,
        uint256 newCost,
        bool newRequiresAuthorization,
        bool newRequiresRefererToBeSet,
        address newPaymentToken
    ) external {
        if (referralPrograms[key].owner != msg.sender) revert Errors.NotAllowed();
        if (newCost != 0 && !newRequiresRefererToBeSet) revert Errors.InvalidParam();

        referralPrograms[key] = ReferralProgram({
            owner: referralPrograms[key].owner,
            requiresAuthorization: newRequiresAuthorization,
            cost: newCost,
            requiresRefererToBeSet: newRequiresRefererToBeSet,
            paymentToken: newPaymentToken
        });
        emit ReferralProgramModified(key, newCost, newRequiresAuthorization, newRequiresRefererToBeSet, newPaymentToken);
    }

    /// @notice Marks an address as allowed to be a referrer for a specific referral key
    /// @param key The referral key for which the address is allowed
    /// @param user The address to be marked as allowed
    function allowReferrer(string calldata key, address user) external {
        if (referralPrograms[key].owner != msg.sender) revert Errors.NotAllowed();
        refererStatus[key][user] = ReferralStatus.Allowed;
        emit ReferrerAdded(key, user);
    }

    /// @notice Allows a user to become a referrer for a specific referral key
    /// @param key The referral key for which the user wants to become a referrer
    /// @param referrerCode The code of the referrer
    function becomeReferrer(string calldata key, string calldata referrerCode) external payable {
        if (referralPrograms[key].owner == address(0)) revert Errors.NotAllowed();
        if (codeToReferrer[key][referrerCode] != address(0)) revert Errors.KeyAlreadyUsed();
        ReferralProgram storage program = referralPrograms[key];
        if (program.cost > 0) {
            if (address(program.paymentToken) == address(0)) {
                if (msg.value < program.cost) revert Errors.NotEnoughPayment();
                // Are we sure this is safe? Like couldn't it loop by adding code to `program.owner` while only paying
                // once `program.cost`
                (bool sent, ) = program.owner.call{ value: msg.value }("");
                require(sent, "Failed to send Ether");
            } else {
                IERC20(program.paymentToken).safeTransferFrom(msg.sender, program.owner, program.cost);
            }
        }
        if (program.requiresAuthorization) {
            if (refererStatus[key][msg.sender] != ReferralStatus.Allowed) revert Errors.NotAllowed();
        }
        refererStatus[key][msg.sender] = ReferralStatus.Set;
        referrerCodeMapping[key][msg.sender] = referrerCode;
        codeToReferrer[key][referrerCode] = msg.sender;
        emit ReferrerAdded(key, msg.sender);
    }

    /// @notice Allows a user to acknowledge that they are referred by a referrer
    /// @param key The referral key for which the user is acknowledging the referrer
    /// @param referrer The address of the referrer
    function acknowledgeReferrer(string calldata key, address referrer) public {
        if (keyToUserToReferrer[key][msg.sender] != address(0)) {
            address previousReferrer = keyToUserToReferrer[key][msg.sender];
            address[] storage previousListOfReferred = keyToReferred[key][previousReferrer];
            for (uint256 i = 0; i < previousListOfReferred.length; i++) {
                if (previousListOfReferred[i] == msg.sender) {
                    previousListOfReferred[i] = previousListOfReferred[previousListOfReferred.length - 1];
                    previousListOfReferred.pop();
                    break;
                }
            }
        }
        if (referralPrograms[key].requiresRefererToBeSet) {
            if (refererStatus[key][referrer] != ReferralStatus.Set) revert Errors.RefererNotSet();
        }
        keyToUserToReferrer[key][msg.sender] = referrer;
        keyToReferred[key][referrer].push(msg.sender);
        emit ReferrerAcknowledged(key, msg.sender, referrer);
    }

    /// @notice Allows a user to acknowledge that they are referred by a referrer using a referrer code
    /// @param key The referral key for which the user is acknowledging the referrer
    /// @param referrerCode The code of the referrer
    /// TODO: This function doesn't work when `referralPrograms[key].requiresRefererToBeSet` is false and referrerCode is
    /// not set
    function acknowledgeReferrerByKey(string calldata key, string calldata referrerCode) external {
        address referrer = codeToReferrer[key][referrerCode];
        if (referrer == address(0)) revert Errors.NotAllowed();
        acknowledgeReferrer(key, referrer);
    }

    /// @notice Sets the cost of the referral program
    /// @param _costReferralProgram The new cost of the referral program
    function setCostReferralProgram(uint256 _costReferralProgram) external onlyGovernor {
        costReferralProgram = _costReferralProgram;
        emit CostReferralProgramSet(_costReferralProgram);
    }

    /// @notice Receive function to accept ETH payments
    receive() external payable {
        // Custom logic for receiving ETH can be added here
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    event CostReferralProgramSet(uint256 newCost);
    event ReferrerAcknowledged(string indexed key, address indexed user, address indexed referrer);
    event ReferrerAdded(string indexed key, address indexed referrer);
    event ReferralProgramModified(
        string indexed key,
        uint256 newCost,
        bool newRequiresAuthorization,
        bool newRequiresRefererToBeSet,
        address newPaymentToken
    );
    event ReferralKeyAdded(string indexed key, ReferralProgram program);
    event ReferralKeyRemoved(uint256 index);
    event UpgradeabilityRevoked();

    event Claimed(address indexed user, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIERS                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the `msg.sender` has the governor role
    modifier onlyGovernor() {
        if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /// @notice Checks whether the contract is upgradeable or whether the caller is allowed to upgrade the contract
    modifier onlyUpgradeableInstance() {
        if (upgradeabilityDeactivated == 1) revert Errors.NotUpgradeable();
        else if (!accessControlManager.isGovernor(msg.sender)) revert Errors.NotGovernor();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor() initializer {}
    function initialize(IAccessControlManager _accessControlManager, uint256 _costReferralProgram, address _feeRecipient) external initializer {
        if (address(_accessControlManager) == address(0)) revert Errors.ZeroAddress();
        accessControlManager = _accessControlManager;
        costReferralProgram = _costReferralProgram;
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc UUPSHelper
    function _authorizeUpgrade(address) internal view override onlyUpgradeableInstance {}

    /// @notice Prevents future contract upgrades
    function revokeUpgradeability() external onlyGovernor {
        upgradeabilityDeactivated = 1;
        emit UpgradeabilityRevoked();
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      VIEW FUNCTIONS                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Gets the list of referral keys
    /// @return The list of referral keys
    function getReferralKeys() external view returns (string[] memory) {
        return referralKeys;
    }

    // Why did we add all the below getters?

    /// @notice Gets the details of a referral program
    /// @param key The referral key to get details for
    /// @return The details of the referral program
    function getReferralProgram(string calldata key) external view returns (ReferralProgram memory) {
        return referralPrograms[key];
    }

    /// @notice Gets the referrer status for a specific user and referral key
    /// @param key The referral key to check
    /// @param user The user to check the referrer status for
    /// @return The referrer status of the user for the given key
    function getReferrerStatus(string calldata key, address user) external view returns (ReferralStatus) {
        return refererStatus[key][user];
    }

    /// @notice Gets the referrer for a specific user and referral key
    /// @param key The referral key to check
    /// @param user The user to check the referrer for
    /// @return The referrer of the user for the given key
    function getReferrer(string calldata key, address user) external view returns (address) {
        return keyToUserToReferrer[key][user];
    }

    /// @notice Gets the list of referred users
    /// @param key The referral key to check
    /// @param user The referrer
    function getReferredUsers(string calldata key, address user) external view returns (address[] memory) {
        return keyToReferred[key][user];
    }

    /// @notice Gets the cost of a referral for a specific key
    /// @param key The referral key to check
    /// @return The cost of the referral for the given key
    function getCostOfReferral(string calldata key) external view returns (uint256) {
        return referralPrograms[key].cost;
    }

    /// @notice Gets the payment token of a referral program
    /// @param key The referral key to check
    /// @return The payment token of the referral program
    function getPaymentToken(string calldata key) external view returns (address) {
        return referralPrograms[key].paymentToken;
    }

    /// @notice Checks if a referral program requires authorization
    /// @param key The referral key to check
    /// @return True if the referral program requires authorization, false otherwise
    function requiresAuthorization(string calldata key) external view returns (bool) {
        return referralPrograms[key].requiresAuthorization;
    }

    /// @notice Checks if a referral program requires a referrer to be set
    /// @param key The referral key to check
    /// @return True if the referral program requires a referrer to be set, false otherwise
    function requiresRefererToBeSet(string calldata key) external view returns (bool) {
        return referralPrograms[key].requiresRefererToBeSet;
    }

    /// @notice Gets the status of a referrer for a specific referral key
    /// @param key The referral key to check
    /// @param referrer The referrer to check the status for
    /// @return The status of the referrer for the given key
    function getReferrerStatusByKey(string calldata key, address referrer) external view returns (ReferralStatus) {
        return refererStatus[key][referrer];
    }
}
