// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


// Chainlink Oracle interface - Price Feed Contract Addresses
// https://docs.chain.link/data-feeds/price-feeds/addresses?network=polygon&page=1#ov
interface Oracle {
    function latestAnswer() external view returns (int256);
}

contract NFTime_SingleBrand is ERC721, ERC721Pausable, ERC721URIStorage, AccessControl {
    // Counter to generate tokenIds 
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    
    // Oracle address
    address private oracleAddress = 0x001382149eBa3441043c1c66972b4772963f5D43;

    // Events
    event CertifierAdded(address indexed certifierAddress, string certifierName);
    event CertifierRemoved(address indexed certifierAddress, string certifierName);
    event ChangedCommissionRecipient(address indexed oldCommissionRecipient, address indexed newCommissionReceiver);
    event TokenBurned(address indexed certifierAddress, uint256 tokenId);
    
    // Roles
    bytes32 public constant BRAND_ROLE_BURNER = keccak256("BRAND_ROLE_BURNER");
    bytes32 public constant CERTIFIER_ROLE_MINTER = keccak256("CERTIFIER_ROLE_MINTER");
    bytes32 public constant NFTIME_ROLE_PAUSER = keccak256("NFTIME_ROLE_PAUSER");
    
    // Define a structure for certifiers and tokens
    struct Certifier {
        address certifierAddress;
        string certifierName;
    }

    // List/mappinns
    Certifier[] private certifiers;
    mapping(address => uint256[]) private certifierTokens; // Who minted the NFT
    mapping(address => uint256[]) private customerTokens;  // Who owns the NFT
    mapping(uint256 => address) private tokenCertifiers;
    mapping(uint256 => int256) private tokenPrices;
    
    // Address to receive the commission
    address private transferCommissionRecipient;

    // Commission 
    int256 private commission = 5; // for thousand --> 5/1000 --> 0.5%
    
    // Constructor
    constructor(address initialOwner) ERC721("NFTime_SingleBrand", "WTC")
    {
        // Assiging roles
        _grantRole(BRAND_ROLE_BURNER, initialOwner);   // The brand role - has the possibility to burn tokens if needed - owner of the contract itself
        _grantRole(NFTIME_ROLE_PAUSER, msg.sender);    // Our company (NFTime) - has the possibility to puase/block the contract funtionalities if needed (e.g. late brand payments)
        
        // Assigning admins
        _setRoleAdmin(CERTIFIER_ROLE_MINTER, BRAND_ROLE_BURNER);
        _setRoleAdmin(NFTIME_ROLE_PAUSER, NFTIME_ROLE_PAUSER);

        _setRoleAdmin(BRAND_ROLE_BURNER, BRAND_ROLE_BURNER);

        // Set tranferCommissionRecipient (BRAND)
        transferCommissionRecipient = initialOwner;
    }

    // ----------
    // Certifiers
    // ----------
    
    // Function to add a certifier --> Manage AccessControl Roles and contract's mapping status
    function addCertifier(address certifierAddress, string memory certifierName) external onlyRole(BRAND_ROLE_BURNER) {
        // Ensure the certifier doesn't already exist
        require(!_certifierExists(certifierAddress), "Certifier already added");

        grantRole(CERTIFIER_ROLE_MINTER, certifierAddress);
        certifiers.push(Certifier(certifierAddress, certifierName));
        emit CertifierAdded(certifierAddress, certifierName);
    }

    // Function to remove a certifier --> Manage AccessControl Roles and contract's mapping status
    function removeCertifier(address certifierAddress) external onlyRole(BRAND_ROLE_BURNER) {
        // Find the index of the certifier in the array
        uint256 index = _findCertifierIndex(certifierAddress);
        require(index < certifiers.length, "Certifier does not exist");

        // Revoke the role
        revokeRole(CERTIFIER_ROLE_MINTER, certifierAddress);
        emit CertifierRemoved(certifierAddress, certifiers[index].certifierName);

        // Remove the certifier from the array
        certifiers[index] = certifiers[certifiers.length - 1];
        certifiers.pop();
    }

    // Returns the list of certifiers
    function getCertifiers() external view returns (Certifier[] memory) {
        return certifiers;
    }

    // Private function to find the index of a certifier in the array
    function _findCertifierIndex(address certifierAddress) private view returns (uint256) {
        for (uint256 i = 0; i < certifiers.length; i++) {
            if (certifiers[i].certifierAddress == certifierAddress) {
                return i;
            }
        }
        return certifiers.length; // Return an invalid index if not found
    }

    // Private function to check if a certifier already exists
    function _certifierExists(address certifierAddress) private view returns (bool) {
        for (uint256 i = 0; i < certifiers.length; i++) {
            if (certifiers[i].certifierAddress == certifierAddress) {
                return true;
            }
        }
        return false;
    }
    
    // -----
    // Token
    // -----

    // Function to mint/generate a NFT
    function safeMint(address to, string memory token_URI, int256 watchPrice) external onlyRole(CERTIFIER_ROLE_MINTER) returns (uint256) 
    {     
        // Token generation and assegnation   
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(to, newItemId);
        _setTokenURI(newItemId, token_URI);

        // Contract's mapping update
        tokenCertifiers[newItemId] = msg.sender;
        tokenPrices[newItemId] = watchPrice;
        certifierTokens[msg.sender].push(newItemId);
        customerTokens[to].push(newItemId);
        
        return newItemId;
    }

    // Function to transfer the ownership of a token --> pay commission to the brand (commission recipient)
    function transferToken(address from, address to, uint256 tokenId) external payable
    {
        // Check requirements
        require(ownerOf(tokenId) == from, "Sender is not the owner of the token");
        require(msg.sender == from, "Only the owner can initiate the transfer");

        // Remove the token from the old owner's customer tokens list
        _removeTokenFromCustomer(from, tokenId);

        // Perform the transfer
        _transfer(from, to, tokenId);

        // Pay brand commission: Get watch price --> calculate commission --> convert in MATIC (Wei)
        uint commissionValue = uint(getCommissionValue(tokenId));  // Certification payment off-chain
        require(msg.value >= commissionValue, "Not enough commission sent"); // Certification payment off-chain
        payable(transferCommissionRecipient).transfer(commissionValue); // Certification payment off-chain

        // Update customer tokens for the new owner
        customerTokens[to].push(tokenId);

        // Emit a Transfer event (ERC721 already emits Transfer event)
        emit Transfer(from, to, tokenId);
    }

    // Returns the list of tokens of a given certifier (Who minted the tokens)
    function getCertifierTokens(address certifierAddress) external view returns (uint256[] memory) {
        return certifierTokens[certifierAddress];
    }

    // Returns the list of tokens of a given customer (Who owns the tokens)
    function getCustomerTokens(address customerAddress) external view returns (uint256[] memory) {
        return customerTokens[customerAddress];
    }

    // Private function to burn/delete a single token --> Manages also the contract's mapping status 
    function burnToken(uint256 tokenId) private {
        // Check
        require(_tokenExists(tokenId), "Token does not exist");
        address certifier = tokenCertifiers[tokenId];
        require(certifier != address(0), "Token has no certifier");

        // Get the owner        
        address owner = this.ownerOf(tokenId);

        // Burn
        _burn(tokenId);
        emit TokenBurned(certifier, tokenId);

        // Remove token data from mappings
        _removeTokenFromCertifier(certifier, tokenId);
        _removeTokenFromCustomer(owner, tokenId);
        delete tokenCertifiers[tokenId];
        delete tokenPrices[tokenId];
    }

    // Funtion to delete/burn a token given the tokenID
    function burnSingleToken(uint256 tokenId) external onlyRole(BRAND_ROLE_BURNER) {
        burnToken(tokenId);        
    }

    // Funtion to delete/burn all the tokens minted by a specific certifier
    function burnTokensByCertifier(address certifierAddress) external onlyRole(BRAND_ROLE_BURNER)
    {
        uint256[] memory tokens = certifierTokens[certifierAddress];
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenId = tokens[i];
            burnToken(tokenId);
        }
        delete certifierTokens[certifierAddress];
    }

    // Custom function to check if a token exists
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
    
    // Utility function to remove a token from the certifierTokens list
    function _removeTokenFromCertifier(address certifier, uint256 tokenId) internal {
        uint256[] storage  tokens = certifierTokens[certifier];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }

    // Utility function to remove a token from the customerTokens list
    function _removeTokenFromCustomer(address customer, uint256 tokenId) internal {
        uint256[] storage  tokens = customerTokens[customer];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }
    
    // ----------
    // Commission
    // ----------

    // Function to update the price of a token --> it is not in the token metadata because it might change  
    function setTokenPrice(uint256 tokenId, int256 price) external onlyRole(CERTIFIER_ROLE_MINTER) {
        require(_tokenExists(tokenId), "Token does not exist");
        tokenPrices[tokenId] = price;
    }

    // Function to get the token price
    function getTokenPrice(uint256 tokenId) external view returns (int256) {
        require(_tokenExists(tokenId), "Token does not exist");
        return tokenPrices[tokenId];
    }
    
    // Function to update the commision "percetage"
    function updateCommission(int newCommission) external onlyRole(BRAND_ROLE_BURNER){
        commission = newCommission;
    }

    // Function to get the commission "percentage" value
    function getCommission() public view onlyRole(BRAND_ROLE_BURNER) returns(int){
        return commission;
    }

    // Function to change/update the Brand role/commission recipient address
    function tranferBrandAddressOwnership(address newAddress) external onlyRole(BRAND_ROLE_BURNER) returns(address) {
        // Only the brand address (commission recipient) can do this method
        require(msg.sender == transferCommissionRecipient,  "Only the brand can tranfer the commission recipient and the ROLE ");

        // Change recipient
        transferCommissionRecipient = newAddress;

        // Manage role
        grantRole(BRAND_ROLE_BURNER, newAddress);
        renounceRole(BRAND_ROLE_BURNER, msg.sender);    

        // Emit event 
        emit ChangedCommissionRecipient(msg.sender, newAddress);
        
        return msg.sender;
    }

    // Funtion to get the final commission value of a given token
    function getCommissionValue(uint256 tokenId) public view returns(int)
    {
        // Get MATIC current fiat price from chainlink oracle
        int currentFiatPrice = Oracle(oracleAddress).latestAnswer();
        require(currentFiatPrice > 0, "Oracle output is Zero or a Negative Value");

        // Get WatchPrice and calculate the fee price
        int256 precisionMultiplier = 1e10;
        int256 tmpPrice = tokenPrices[tokenId] * precisionMultiplier;
        int256 fee = (tmpPrice/1000) * commission;
        
        // Convert units from USD/EUR to MATIC/Wei
        int256 fiatFeePrice = fee * 1e18;
        int256 feeWeiAmount = (fiatFeePrice * 1e8) / currentFiatPrice;
        feeWeiAmount = feeWeiAmount / precisionMultiplier;

        return feeWeiAmount;
    }

    // --------
    // Contract
    // --------

    // Function to pause the contract functionalities (mint)
    function pause() external onlyRole(NFTIME_ROLE_PAUSER){
        _pause();
    }

    // Function to unpause the contract functionalities (mint)
    function unpause() external onlyRole(NFTIME_ROLE_PAUSER) {
        _unpause();
    }

    // Funtion to update the oracle address (in case it changes or different blockchain usage)
    function updateOracleAddress(address newContractAddress) external onlyRole(NFTIME_ROLE_PAUSER){
        oracleAddress = newContractAddress;
    }

    // Function to get the oracle address
    function getOracleAddress() public view onlyRole(NFTIME_ROLE_PAUSER) returns(address){
        return oracleAddress;
    }

    // -------------------
    // Library / Overrides
    // -------------------

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage, AccessControl) returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Pausable) returns (address)
    {
        return super._update(to, tokenId, auth);
    }
}