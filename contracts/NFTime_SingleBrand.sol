// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// TODO:
// - OK Figura admin per bloccare tutto e farsi pagare da brand (PAUSER);
// - OK Sostituire buy con transfer;
// - OK Implementare uso corretto dei ruoli;

// - Pagamento per minting tramite oracolo --> NO Perchè pagamento fatto off-chain (vedi excel SIMO)
// + penso a logica di upgrade se necessaria;

// OK Valutare inserimento burn tra le features (i.e. per certificatori "corrotti") -> memorizzazione dell'associazione <certificatori, NFT mintati>;
    // - OK Salvataggio tokenID degli NFT (isn't this stored in ERC721?);
    // - OK Burning di tutti gli NFT di un dato certificatore dopo una certa data;
    // - OK NO DATA - Metodo che restituisca lista NFT con certificatore e data di certificazione;

// - OK Metodo che ritorna la lista dei certificatori;

// - Valutare quali altri eventi aggiungere per tenere traccia delle transazioni più importanti;

// NEW TODO
// OK --> da testare - Set Commission Recipient nel costruttore
// con pietro --> Controllo metodo per aggiornare il commission recipient
// OK --> da testare -  Salvo i prezzi in fase di MINTING per calcolare anche il tasso/commissione
// OK --> da testare - Trasformo mapping ceritifiers in lista per tornare la lista
// Controllo e verifico tutto --> creo un history/path logico da seguire simile real world 

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
    
    // Define a structure for certifiers
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
        _setRoleAdmin(NFTIME_ROLE_PAUSER, NFTIME_ROLE_PAUSER); // x PIETRO --> Perchè così? me lo spieghi?

        // Set tranferCommissionRecipient (BRAND)
        transferCommissionRecipient = initialOwner;
    }

    // ----------
    // Certifiers
    // ----------
    
    function addCertifier(address certifierAddress, string memory certifierName) external onlyRole(BRAND_ROLE_BURNER) {
        // Ensure the certifier doesn't already exist
        require(!_certifierExists(certifierAddress), "Certifier already added");

        grantRole(CERTIFIER_ROLE_MINTER, certifierAddress);
        certifiers.push(Certifier(certifierAddress, certifierName));
        emit CertifierAdded(certifierAddress, certifierName);
    }

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

    function safeMint(address to, string memory token_URI, int256 watchPrice) external onlyRole(CERTIFIER_ROLE_MINTER) returns (uint256) 
    {        
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(to, newItemId);
        _setTokenURI(newItemId, token_URI);

        tokenCertifiers[newItemId] = msg.sender;
        tokenPrices[newItemId] = watchPrice;
        certifierTokens[msg.sender].push(newItemId);
        customerTokens[to].push(newItemId);
        
        return newItemId;
    }

    function transferToken(address from, address to, uint256 tokenId) external payable
    {
        require(ownerOf(tokenId) == from, "Sender is not the owner of the token");
        require(msg.sender == from, "Only the owner can initiate the transfer");

        // Remove the token from the old owner's customer tokens list
        removeTokenFromCustomer(from, tokenId);

        // Perform the transfer
        _transfer(from, to, tokenId);

        // Pay brand commission
        // Get price (from tokenURI?)
        // TODO: Use here chainlink Oracle to calculate the WEI amount to pay
        uint commissionValue = uint(getCommissionValue(tokenId));  // Certification payment off-chain
        require(msg.value >= commissionValue, "Not enough commission sent"); // Certification payment off-chain
        payable(transferCommissionRecipient).transfer(commissionValue); // Certification payment off-chain

        // Update customer tokens for the new owner
        customerTokens[to].push(tokenId);

        // Emit a Transfer event (ERC721 already emits Transfer event)
        emit Transfer(from, to, tokenId);
    }

    function getCertifierTokens(address certifierAddress) external view returns (uint256[] memory) {
        return certifierTokens[certifierAddress];
    }

    function burnToken(uint256 tokenId) external onlyRole(BRAND_ROLE_BURNER) {
        // Check
        require(_tokenExists(tokenId), "Token does not exist");
        address certifier = tokenCertifiers[tokenId];
        require(certifier != address(0), "Token has no certifier");

        // Burn
        _burn(tokenId);
        emit TokenBurned(certifier, tokenId);

        // Remove token data
        _removeTokenFromCertifier(certifier, tokenId);
        delete tokenCertifiers[tokenId];
        delete tokenPrices[tokenId];
    }

    function burnTokensByCertifier(address certifierAddress) external onlyRole(BRAND_ROLE_BURNER)
    {
        uint256[] memory tokens = certifierTokens[certifierAddress];
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenId = tokens[i];
            if (_tokenExists(tokenId)) {
                _burn(tokenId);
                emit TokenBurned(certifierAddress, tokenId);
                
                delete tokenCertifiers[tokenId];
                delete tokenPrices[tokenId];
            }
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
    
    // Funzione di utilità per rimuovere un token dalla lista di un certificatore
    function _removeTokenFromCertifier(address certifier, uint256 tokenId) internal {
        uint256[] storage tokens = certifierTokens[certifier];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }

    function removeTokenFromCustomer(address customer, uint256 tokenId) internal
    {
        uint256[] storage tokens = customerTokens[customer];
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

    // updatePrice - CERTIFIERS
    function setTokenPrice(uint256 tokenId, int256 price) external onlyRole(CERTIFIER_ROLE_MINTER) {
        require(_tokenExists(tokenId), "Token does not exist");
        tokenPrices[tokenId] = price;
    }

    // getPrice
    function getTokenPrice(uint256 tokenId) external view returns (int256) {
        require(_tokenExists(tokenId), "Token does not exist");
        return tokenPrices[tokenId];
    }
    
    // updateCommision - BRAND
    function updateCommission(int newCommission) external onlyRole(BRAND_ROLE_BURNER){
        commission = newCommission;
    }

    // getCommission
    function getCommission() public view onlyRole(BRAND_ROLE_BURNER) returns(int){
        return commission;
    }

    // Brand choose/update the recipient address
    function setTransferCommissionRecipient(address newRecipient) external onlyRole(BRAND_ROLE_BURNER) {
        address oldRecipient = transferCommissionRecipient;
        transferCommissionRecipient = newRecipient;
        emit ChangedCommissionRecipient(oldRecipient, newRecipient);

        // TODO CHECK CON PIETRO --> Va al brand, non a NFTime la commissione.
        // Bisogna cambiare anche chi è il ruolo del brand? NON CREDO perche altrimenti cabierebbe la ownership etc e non va bene
        // Secondo me questa cosa, vista la commissione al brand e non a noi va solo cancellata ma vorrei ragionarci assieme

        // grantRole(NFTIME_ROLE_PAUSER, newRecipient);
        // renounceRole(NFTIME_ROLE_PAUSER, msg.sender); // x PIETRO --> SICURO CHE QUA NON SIA oldRecipient invece di msg.sender?    
    }

    function getCommissionValue(uint256 tokenId) public view onlyRole(BRAND_ROLE_BURNER) returns(int)
    {
        // Get MATIC current fiat price from chainlink oracle
        int currentFiatPrice = Oracle(oracleAddress).latestAnswer();
        require(currentFiatPrice > 0, "Oracle output is Zero or a Negative Value");

        // Get WatchPrice
        int256 tmpPrice = tokenPrices[tokenId];
        int256 fee = (tmpPrice/1000) * commission;
        
        // Calculate the fee frice in MATIC [WEI]
        int256 fiatFeePrice = fee * 1e18;
        int256 precisionMultiplier = 1e10;
        int256 feeWeiAmount = (fiatFeePrice * precisionMultiplier * 1e8) / currentFiatPrice;
        feeWeiAmount = feeWeiAmount / precisionMultiplier;

        // return fee in WEI 
        return feeWeiAmount;

        // Converti il valore da Wei a MATIC
        //int256 matic = weiAmount / 1e18; // Converti da Wei a MATIC dividendo per 1e18
        //return matic; // Ritorna il valore in MATIC
    }

    // --------
    // Contract
    // --------

    function pause() external onlyRole(NFTIME_ROLE_PAUSER) {
        _pause();
    }

    function unpause() external onlyRole(NFTIME_ROLE_PAUSER) {
        _unpause();
    }

    function updateOracleAddress(address newContractAddress) external onlyRole(NFTIME_ROLE_PAUSER){
        oracleAddress = newContractAddress;
    }

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
