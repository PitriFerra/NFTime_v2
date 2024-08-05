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

// - Valutare inserimento burn tra le features (i.e. per certificatori "corrotti") -> memorizzazione dell'associazione <certificatori, NFT mintati>;
    // - Salvataggio tokenID degli NFT (isn't this stored in ERC721?);
    // - Burning di tutti gli NFT di un dato certificatore dopo una certa data;
    // - Metodo che restituisca lista NFT con certificatore e data di certificazione;

// - Metodo che ritorna la lista dei certificatori;

// - Valutare quali altri eventi aggiungere per tenere traccia delle transazioni più importanti;

// Chainlink Oracle interface - Price Feed Contract Addresses
// https://docs.chain.link/data-feeds/price-feeds/addresses?network=polygon&page=1#ov
interface Oracle {
    function latestAnswer() external view returns (int256);
}

contract NFTime_SingleBrand is ERC721, ERC721Pausable, ERC721URIStorage, AccessControl {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // List of certifiers with their minted tokens
    mapping(address => string) private certifiers;
    mapping(address => uint256[]) private certifierTokens;
    mapping(uint256 => address) private tokenCertifiers;

    // Oracle address
    address private oracleAddress = 0x001382149eBa3441043c1c66972b4772963f5D43;

    // Address to receive the commission
    address private commissionRecipient;

    // Roles
    bytes32 public constant BRAND_ROLE_BURNER = keccak256("BRAND_ROLE_BURNER");
    bytes32 public constant CERTIFIER_ROLE_MINTER = keccak256("CERTIFIER_ROLE_MINTER");
    bytes32 public constant NFTIME_ROLE_PAUSER = keccak256("NFTIME_ROLE_PAUSER");

    // Events
    event CertifierAdded(address indexed certifierAddress, string certifierName);
    event CertifierRemoved(address indexed certifierAddress, string certifierName);
    event ChangedCommissionRecipient(address indexed oldCommissionRecipient, address indexed newCommissionReceiver);
    event TokenBurned(address indexed certifierAddress, uint256 tokenId);

    // Constructor
    constructor(address initialOwner) ERC721("Rolex_NFTime", "WTC")
    {
        _grantRole(BRAND_ROLE_BURNER, initialOwner);
        _grantRole(NFTIME_ROLE_PAUSER, msg.sender);
        _setRoleAdmin(CERTIFIER_ROLE_MINTER, BRAND_ROLE_BURNER);
        _setRoleAdmin(NFTIME_ROLE_PAUSER, NFTIME_ROLE_PAUSER);
    }

    // ----------------------------
    // Methods - only owner (BRAND)
    // ----------------------------

    function addCertifier(address certifierAddress, string memory certifierName) external onlyRole(BRAND_ROLE_BURNER) 
    {
        grantRole(CERTIFIER_ROLE_MINTER, certifierAddress);
        certifiers[certifierAddress] = certifierName;
        emit CertifierAdded(certifierAddress, certifierName);
    }

    function removeCertifier(address certifierAddress) external onlyRole(BRAND_ROLE_BURNER)
    {
        revokeRole(CERTIFIER_ROLE_MINTER, certifierAddress);
        emit CertifierRemoved(certifierAddress, certifiers[certifierAddress]);
        delete certifiers[certifierAddress];
    }

    function burnToken(uint256 tokenId) external onlyRole(BRAND_ROLE_BURNER) {
        require(tokenExists(tokenId), "Token does not exist");
        address certifier = tokenCertifiers[tokenId];
        require(certifier != address(0), "Token has no certifier");

        // Rimuovere il token dalla lista del certificatore
        removeTokenFromCertifier(certifier, tokenId);

        _burn(tokenId);
        emit TokenBurned(certifier, tokenId);
    }

    function burnTokensByCertifier(address certifierAddress) external onlyRole(BRAND_ROLE_BURNER)
    {
        uint256[] memory tokens = certifierTokens[certifierAddress];
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenId = tokens[i];
            if (tokenExists(tokenId)) {
                _burn(tokenId);
                emit TokenBurned(certifierAddress, tokenId);
            }
        }
        delete certifierTokens[certifierAddress];
    }

    function getCertifierTokens(address certifierAddress) external view returns (uint256[] memory) {
        return certifierTokens[certifierAddress];
    }

    // ---------------------------------------
    // Methods - commission recipient (NFTime)
    // ---------------------------------------

    function setCommissionRecipient(address recipient) external onlyRole(NFTIME_ROLE_PAUSER) {
        address oldRecipient = commissionRecipient;
        commissionRecipient = recipient;
        grantRole(NFTIME_ROLE_PAUSER, recipient);
        renounceRole(NFTIME_ROLE_PAUSER, msg.sender); // x PIETRO --> SICURO CHE QUA NON SIA oldRecipient invece di msg.sender? 
        emit ChangedCommissionRecipient(oldRecipient, recipient);
    }

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

    // -------------------------
    // Methods - only certifiers
    // -------------------------

    function getCommissionValue(int256 watchPrice) public view returns(int) {
        int currentFiatPrice = Oracle(oracleAddress).latestAnswer();
        require(currentFiatPrice > 0, "Oracle output is Zero or a Negative Value");
        int256 fiatPrice = watchPrice * 1e18;
        int256 precisionMultiplier = 1e10;
        int256 weiAmount = (fiatPrice * precisionMultiplier * 1e8) / currentFiatPrice;
        weiAmount = weiAmount / precisionMultiplier;
        return weiAmount;

        // Converti il valore da Wei a MATIC
        //int256 matic = weiAmount / 1e18; // Converti da Wei a MATIC dividendo per 1e18
        //return matic; // Ritorna il valore in MATIC
    }

    function safeMint(address to, string memory token_URI) external payable onlyRole(CERTIFIER_ROLE_MINTER) returns (uint256) 
    {
        //uint commissionValue = uint(getCommissionValue());  // Certification payment off-chain
        //require(msg.value >= commissionValue, "Not enough commission sent"); // Certification payment off-chain
        //payable(commissionRecipient).transfer(commissionValue); // Certification payment off-chain
        
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(to, newItemId);
        _setTokenURI(newItemId, token_URI);

        tokenCertifiers[newItemId] = msg.sender;
        certifierTokens[msg.sender].push(newItemId);
        
        return newItemId;
    }

    // -----
    // UTILS
    // -----

    // Custom function to check if a token exists
    function tokenExists(uint256 tokenId) public view returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
    
    // Funzione di utilità per rimuovere un token dalla lista di un certificatore
    function removeTokenFromCertifier(address certifier, uint256 tokenId) internal {
        uint256[] storage tokens = certifierTokens[certifier];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }

    // ---------------------
    // Overrides (necessary)
    // ---------------------

    function tokenURI(uint256 tokenId) 
        public 
        view 
        override(ERC721, ERC721URIStorage) 
        returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721, ERC721URIStorage, AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
}
