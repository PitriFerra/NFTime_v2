// SPDX-License-Identifier: UNLICENSED 
// MyContract.sol
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

// Aspettare di usarli prima di mettere: Ownable
contract NFTime is ERC721, ERC721URIStorage{
    // Nessun guadagno tramite la blockchain. Tutto offchain

    // TODO:
    // OK Logica minting e trasferimento NFTs
    // Capire se tenere i metodi public o farli external (io li farei external se non hanno chiamate interne perché così andiamo a risparmiare gas)
    // Capire se tenere i modifier o meno (io direi solo se usati molte volte nello smart contract)
    // Gestione dei ruoli (come viene inserito un brand piuttosto che come viene "eletto" un certificatore):
        // WAIT Funzione per aggiungere un certificatore (es. i brand possono aggiungerli -> penso alla logica (vedere cosa dicono Simo e Mario))
    // Capire come vengono gestiti gli NFT nei progetti gia esistenti e di successo


    // ------------
    // Data Structs
    // ------------

    struct CertifierData
    {
        string name;
        bool isActive;
    }


    // --------------------------
    // Global / private variables
    // --------------------------
    
    // Contract owner address
    address private contractOwner;
    // List of certifiers
    mapping(address => CertifierData) private certifiers;
    // Counter for NFT IDs
    uint256 private _tokenIds;
    

    // --------------------
    // constructor
    // --------------------
    
    constructor(string memory brandName, string memory collectionName, string memory symbol) ERC721(collectionName, symbol)
    { 
        contractOwner = msg.sender;
        addCertifier(msg.sender, brandName); // Brand address is set as certifier as well so that it can mint too
    }


    // --------------------
    // Methods - only owner
    // --------------------
    
    addCertifier(address certifierAddress, string memory certifierName) public
    {
        require(msg.sender == contractOwner, "Only the contract owner can perform this operation");
        certifiers[certifierAddress].name = certifierName;
        certifiers[certifierAddress].isActive = true;
    }

    removeCertifier(address certifierAddress) external
    {
        require(msg.sender == contractOwner, "Only the contract owner can perform this operation");
        certifiers[certifierAddress].isActive = false;
    }


    // -------------------------
    // Methods - only certifiers
    // -------------------------

    function mintNFT(address recipient, string memory tokenURI) external returns (uint256) {
        require(certifiers[msg.sender].isActive, "Only active 'certifiers' can perform this operation");
        _tokenIds++;
        _mint(recipient, _tokenIds);
        _setTokenURI(_tokenIds, tokenURI);
        return _tokenIds;
    }


    // ------------------
    // Methods - everyone
    // ------------------

    function transferFrom(address _from, address _to, uint256 _tokenId) public override {
        require(msg.sender == _from, "You can only transfer your own token");
        super.transferFrom(_from, _to, _tokenId);
    }
}