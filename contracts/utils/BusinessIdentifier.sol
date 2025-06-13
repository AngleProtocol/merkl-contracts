

// SPDX-License-Identifier: BUSL-1.1


pragma solidity ^0.8.17;




import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";


import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";




interface IBusinessPermission {


 function requestBusinessPermissionForUser(address _walletAddress) external;




 function removeBusinessPermissionForUser(address _walletAddress) external;


}




enum Action {


 ADD,


 REMOVE


}




/**


 * @title BusinessContract


 * @dev A contract that represents a business entity.


 */


contract BusinessIdentifier is AccessControlUpgradeable, UUPSUpgradeable {


 /**


 * @dev Role identifier for authorized representatives. (Directors or Office holders)


 */


 bytes32 public constant AUTHORISED_REPRESENTATIVE_ROLE =


 keccak256("AUTHORISED_REPRESENTATIVE");


 /**


 * @dev Role identifier for authorized delegates. (Contractors, Developers, etc.)


 */


 bytes32 public constant AUTHORISED_DELEGATE_ROLE =


 keccak256("AUTHORISED_DELEGATE"); // Contractor, Developers, etc..




 /**


 * @dev The name of the company.


 */


 string public companyName;




 /**


 * @dev The incorporated name of the company.


 */


 string public incorporatedName;




 /**


 * @dev The type of identifier for the company.


 */


 string public identifierType;




 /**


 * @dev The identifier for the company.


 */


 string public identifier;




 /**


 * @dev The business address of the company.


 */


 string public businessAddress;




 /**


 * @dev Boolean indicating if the entity is the beneficial owner of the assets it is managing.


 */


 bool public isBeneficialOwner;




 /**


 * @dev An array storing the addresses of smart contracts owned by the business.


 */


 address[] public smartContracts;




 /**


 * @dev Sets the max limit for batch operations to prevent high gas usage.


 */


 uint256 public batchLimit;




 /**


 * @dev Creates interface to reference AllowedList contract.


 */


 IBusinessPermission private _businessPermission;




 error UnauthorisedAccess(string);


 error InvalidAddress(string);


 error BatchSizeExceeded(uint256 actualSize, uint256 maxSize);


 error EmptyAddressArray();


 error InvalidBatchLimit(uint256 limit);


 error RoleUpdateFailed(string);




 /**


 * @dev Initializes the contract with the provided parameters.


 * @param _admin The address of the admin account.


 * @param _companyName The name of the company.


 * @param _incorporatedName The incorporated name of the company.


 * @param _identifierType The type of identifier for the company.


 * @param _identifier The identifier for the company.


 * @param _businessAddress The business address of the company.


 * @param _isBeneficialOwner Boolean indicating if the entity is the beneficial owner of the assets it is managing.


 * @param _businessPermissionAddress The address of the business permission contract.


 */


 function initialize(


 address _admin,


 string memory _companyName,


 string memory _incorporatedName,


 string memory _identifierType,


 string memory _identifier,


 string memory _businessAddress,


 bool _isBeneficialOwner,


 address _businessPermissionAddress


 ) public initializer {


 __AccessControl_init();


 __UUPSUpgradeable_init();


 // Grant the Admin role to a specified account


 _grantRole(DEFAULT_ADMIN_ROLE, _admin);




 companyName = _companyName;


 incorporatedName = _incorporatedName;


 identifierType = _identifierType;


 identifier = _identifier;


 businessAddress = _businessAddress;


 isBeneficialOwner = _isBeneficialOwner;


 _businessPermission = IBusinessPermission(_businessPermissionAddress);


 batchLimit = 100;


 }




 /**


 * @dev Event emitted when a smart contract address is added.


 * @param _address The address of the smart contract.


 * @param _by The address of the caller.


 */


 event SmartContractAdded(address indexed _address, address indexed _by);




 /**


 * @dev Event emitted when a smart contract address is removed.


 * @param _address The address of the smart contract.


 * @param _by The address of the caller.


 */


 event SmartContractRemoved(address indexed _address, address indexed _by);




 /**


 * @dev Event emitted when a role is updated.


 * @param userAddress The address of the user whose role was updated.


 * @param role The role that was updated.


 * @param action The action performed (ADD or REMOVE).


 * @param message Additional information about the update.


 */


 event RoleUpdated(


 address indexed userAddress,


 bytes32 indexed role,


 Action action,


 string message


 );




 event AddressDoesNotExist(address indexed _address, bytes32 indexed role);


 event RoleAlreadyExists(address indexed _address, bytes32 indexed role);


 /**


 * @dev Modifier that allows only contract owner to execute a function.


 */


 modifier onlyAdmin() {


 if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {


 revert UnauthorisedAccess("Caller must be IDP");


 }


 _;


 }


 /**


 * @dev Modifier that allows only authorized representatives or contract owner to execute a function.


 */


 modifier onlyAuthorisedRepresentative() {


 if (


 !hasRole(AUTHORISED_REPRESENTATIVE_ROLE, _msgSender()) &&


 !hasRole(DEFAULT_ADMIN_ROLE, _msgSender())


 ) {


 revert UnauthorisedAccess(


 "Caller must have IDP or Authorised Representative"


 );


 }


 _;


 }


 /**


 * @dev Modifier that allows only authorized delegates or authorized representatives or contract owner to execute a function.


 */


 modifier onlyAuthorisedDelegate() {


 if (


 !hasRole(AUTHORISED_DELEGATE_ROLE, _msgSender()) &&


 !hasRole(AUTHORISED_REPRESENTATIVE_ROLE, _msgSender()) &&


 !hasRole(DEFAULT_ADMIN_ROLE, _msgSender())


 ) {


 revert UnauthorisedAccess(


 "Caller must have IDP or Authorised Representative or Authorised Delegate"


 );


 }


 _;


 }




 /**


 * @dev Modifier to validate batch size and non-empty address array.


 * @param _addresses The array of addresses to check.


 */


 modifier validateBatchSize(address[] memory _addresses) {


 if (_addresses.length == 0) {


 revert EmptyAddressArray();


 }


 if (_addresses.length > batchLimit) {


 revert BatchSizeExceeded(_addresses.length, batchLimit);


 }


 _;


 }




 /**


 * @dev Event emitted when the company name is updated.


 * @param _companyName The updated company name.


 */


 event UpdatedCompanyName(string _companyName);




 /**


 * @dev Event emitted when the incorporated name is updated.


 * @param _incorporatedName The updated incorporated name.


 */


 event UpdatedIncorporatedName(string _incorporatedName);




 /**


 * @dev Event emitted when the identifier type is updated.


 * @param _identifierType The updated identifier type.


 */


 event UpdatedIdentifierType(string _identifierType);




 /**


 * @dev Event emitted when the identifier is updated.


 * @param _identifier The updated identifier.


 */


 event UpdatedIdentifier(string _identifier);




 /**


 * @dev Event emitted when the business address is updated.


 * @param _businessAddress The updated business address.


 */


 event UpdatedBusinessAddress(string _businessAddress);




 /**


 * @dev Event emitted when the beneficial owner status updated.


 * @param _isBeneficialOwner The updated beneficial owner status.


 */


 event UpdatedIsBeneficialOwner(bool _isBeneficialOwner);




 /**


 * @dev Updates the company name.


 * @param _companyName The updated company name.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function updateCompanyName(string memory _companyName) external onlyAdmin {


 companyName = _companyName;


 emit UpdatedCompanyName(_companyName);


 }




 /**


 * @dev Updates the incorporated name.


 * @param _incorporatedName The updated incorporated name.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */




 function updateIncorporatedName(


 string memory _incorporatedName


 ) external onlyAdmin {


 incorporatedName = _incorporatedName;


 emit UpdatedIncorporatedName(_incorporatedName);


 }




 /**


 * @dev Updates the identifier type.


 * @param _identifierType The updated identifier type.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function updateIdentifierType(


 string memory _identifierType


 ) external onlyAdmin {


 identifierType = _identifierType;


 emit UpdatedIdentifierType(_identifierType);


 }




 /**


 * @dev Updates the identifier.


 * @param _identifier The updated identifier.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function updateIdentifier(string memory _identifier) external onlyAdmin {


 identifier = _identifier;


 emit UpdatedIdentifier(_identifier);


 }




 /**


 * @dev Updates the business address.


 * @param _businessAddress The updated business address.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function updateBusinessAddress(


 string memory _businessAddress


 ) external onlyAdmin {


 businessAddress = _businessAddress;


 emit UpdatedBusinessAddress(_businessAddress);


 }




 /**


 * @dev Updates the beneficial owner status.


 * @param _isBeneficialOwner The updated beneficial owner status.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function updateIsBeneficialOwner(


 bool _isBeneficialOwner


 ) external onlyAdmin {


 isBeneficialOwner = _isBeneficialOwner;


 emit UpdatedIsBeneficialOwner(_isBeneficialOwner);


 }




 /**


 * @dev Adds addresses as authorized representatives.


 * @param _addresses The addresses to be added as authorized representatives.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function addAuthorisedRepresentative(


 address[] memory _addresses


 ) external onlyAdmin {


 _updateRole(


 _addresses,


 AUTHORISED_REPRESENTATIVE_ROLE,


 Action.ADD,


 _businessPermission.requestBusinessPermissionForUser


 );


 }




 /**


 * @dev Removes addresses as authorized representatives.


 * @param _addresses The addresses to be removed as authorized representatives.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function removeAuthorisedRepresentative(


 address[] memory _addresses


 ) external onlyAdmin {


 _updateRole(


 _addresses,


 AUTHORISED_REPRESENTATIVE_ROLE,


 Action.REMOVE,


 _businessPermission.removeBusinessPermissionForUser


 );


 }




 /**


 * @dev Adds addresses as authorized delegates.


 * @param _addresses The addresses to be added as authorized delegates.


 * Requirements:


 * - Caller must have the AUTHORISED_REPRESENTATIVE_ROLE.


 */


 function addAuthorisedDelegate(


 address[] memory _addresses


 ) external onlyAuthorisedRepresentative {


 _updateRole(


 _addresses,


 AUTHORISED_DELEGATE_ROLE,


 Action.ADD,


 _businessPermission.requestBusinessPermissionForUser


 );


 }




 /**


 * @dev Removes addresses as authorized delegates.


 * @param _addresses The addresses to be removed as authorized delegates.


 * Requirements:


 * - Caller must have the AUTHORISED_REPRESENTATIVE_ROLE.


 */


 function removeAuthorisedDelegate(


 address[] memory _addresses


 ) external onlyAuthorisedRepresentative {


 _updateRole(


 _addresses,


 AUTHORISED_DELEGATE_ROLE,


 Action.REMOVE,


 _businessPermission.removeBusinessPermissionForUser


 );


 }




 /**


 * @dev Updates roles for a batch of addresses, either adding or removing the role.


 * @param _addresses The list of addresses to update roles for.


 * @param role The role to be updated.


 * @param action The action to perform (ADD or REMOVE).


 * @param businessPermissionFn The function to call for business permission operations (request or remove).


 */


 function _updateRole(


 address[] memory _addresses,


 bytes32 role,


 Action action,


 function(address) external businessPermissionFn


 ) internal validateBatchSize(_addresses) {


 for (uint256 i = 0; i < _addresses.length; ) {


 address _address = _addresses[i];




 bool hasRoleBefore = hasRole(role, _address);


 bool shouldUpdate = (action == Action.ADD && !hasRoleBefore) ||


 (action == Action.REMOVE && hasRoleBefore);




 if (shouldUpdate) {


 try businessPermissionFn(_address) {


 if (action == Action.ADD) {


 _grantRole(role, _address);


 emit RoleUpdated(


 _address,


 role,


 action,


 "Successfully Added"


 );


 } else {


 _revokeRole(role, _address);


 emit RoleUpdated(


 _address,


 role,


 action,


 "Successfully Removed"


 );


 }


 } catch (bytes memory reason) {


 revert RoleUpdateFailed(


 string(abi.encodePacked("Error:", string(reason)))


 );


 }


 }


 unchecked {


 i++;


 }


 }


 }




 /**


 * @dev Sets the max limit for batch operations to prevent high gas usage.


 * The new batch limit value must be greater than 0 and cannot exceed 100.


 * @param _newLimit The new batch limit value to be set.


 */


 function updateBatchLimit(


 uint256 _newLimit


 ) external onlyAuthorisedRepresentative {


 if (_newLimit == 0) revert InvalidBatchLimit(_newLimit);


 batchLimit = _newLimit;


 }




 /**


 * @dev Adds a smart contract address to the list of smart contracts owned by the business.


 * @param _address The address of the smart contract to be added.


 * Requirements:


 * - Caller must be an authorized delegate.


 * - The provided address must not be the zero address.


 */


 function addSmartContract(


 address _address


 ) external onlyAuthorisedDelegate {


 if (_address == address(0)) {


 revert InvalidAddress("Invalid address.");


 }


 smartContracts.push(_address);




 emit SmartContractAdded(_address, _msgSender());


 }




 /**


 * @dev Removes a smart contract address from the list of smart contracts owned by the business.


 * @param _address The address of the smart contract to be removed.


 * Requirements:


 * - Caller must be an authorized delegate.


 */


 function removeSmartContract(


 address _address


 ) external onlyAuthorisedDelegate {


 for (uint256 i = 0; i < smartContracts.length; ) {


 if (smartContracts[i] == _address) {


 smartContracts[i] = smartContracts[smartContracts.length - 1];


 smartContracts.pop();


 break;


 }


 unchecked {


 i++;


 }


 }




 emit SmartContractRemoved(_address, _msgSender());


 }




 /**


 * @dev Internal function to authorize an upgrade to a new implementation.


 * @param newImplementation The address of the new implementation contract.


 * Requirements:


 * - Caller must have the DEFAULT_ADMIN_ROLE.


 */


 function _authorizeUpgrade(


 address newImplementation


 ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}


}

