// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";



// TODO:
// - OK Figura admin per bloccare tutto e farsi pagare da brand (PAUSER);
// - Pagamento per minting tramite oracolo + penso a logica di upgrade se necessaria;
// - OK Sostituire buy con transfer;
// - Valutare inserimento burn tra le features (i.e. per certificatori "corrotti") -> memorizzazione dell'associazione <certificatori, NFT mintati>;
    // - Salvataggio tokenID degli NFT (isn't this stored in ERC721?);
// - Metodo che ritorna la lista dei certificatori;
// - OK Implementare uso corretto dei ruoli;
// - Valutare quali altri eventi aggiungere per tenere traccia delle transazioni più importanti;


contract NFTime_Rolex is ERC721, ERC721Pausable, ERC721URIStorage, AccessControl {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // List of certifiers
    mapping(address => string) private certifiers; // Visto l'utilizzo dei ruoli, ha davvero senso memorizzare
    // i dati sui certificatori all'iterno della Blokchain? Perché non memorizzare questi dati nella DApp?
    // Pensare a vantaggi e svantaggi!


    // Address to receive the commission
    address private commissionRecipient;

    // Roles
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Events
    event CertifierAdded(address indexed certifierAddress, string certifierName);
    event CertifierRemoved(address indexed certifierAddress, string certifierName);
    event ChangedCommissionRecipient(address indexed oldCommissionRecipient, address indexed newCommissionReceiver);
    
    constructor(address initialOwner)
        ERC721("Rolex_NFTime", "WTC")
    {
        _grantRole(BURNER_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, msg.sender);
        _setRoleAdmin(MINTER_ROLE, BURNER_ROLE);
        _setRoleAdmin(PAUSER_ROLE, PAUSER_ROLE);
    }


    // --------------------
    // Methods - only owner
    // --------------------

    function addCertifier(address certifierAddress, string memory certifierName) 
        external 
        onlyRole(BURNER_ROLE) 
    {
        grantRole(MINTER_ROLE, certifierAddress);
        emit CertifierAdded(certifierAddress, certifierName);
    }

    function removeCertifier(address certifierAddress) 
        external 
        onlyRole(BURNER_ROLE)
    {
        revokeRole(MINTER_ROLE, certifierAddress);
        emit CertifierRemoved(certifierAddress, certifiers[certifierAddress]);
    }


    // -----------------------------------
    // Methods - only commission recipient
    // -----------------------------------

    function setCommissionRecipient(address recipient) external onlyRole(PAUSER_ROLE) {
        commissionRecipient = recipient;
        grantRole(PAUSER_ROLE, recipient);
        renounceRole(PAUSER_ROLE, msg.sender);
        emit ChangedCommissionRecipient(msg.sender, recipient);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }


    // -------------------------
    // Methods - only certifiers
    // -------------------------

    function getCommissionValue() pure private returns (uint256) {
        return 10;
    }

    function safeMint(address to, string memory token_URI) 
        external 
        payable 
        onlyRole(MINTER_ROLE) 
        returns (uint256) 
    {
        uint256 commissionValue = getCommissionValue();
        require(msg.value >= commissionValue, "Not enough commission sent");
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _safeMint(to, newItemId);
        _setTokenURI(newItemId, token_URI);
        payable(commissionRecipient).transfer(commissionValue);
        return newItemId;
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