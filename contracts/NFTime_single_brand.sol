// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// TODO:
// - Figura admin per bloccare tutto e farsi pagare da brand;
// - Pagamento per minting tramite oracolo + penso a logica di upgrade se necessaria;
// - Sostituire buy con transfer;
// - Valutare inserimento burn tra le features (i.e. per certificatori "corrotti") -> memorizzazione dell'associazione <certificatori, NFT mintati>;
    // - Salvataggio tokenID degli NFT;

contract NFTime is ERC721, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // Address to receive the 5% commission
    address private commissionRecipient;

    struct CertifierData {
        string name;
        bool isActive;
    }

    struct SaleInfo {
        uint256 price;
        address seller;
    }

    // List of certifiers
    mapping(address => CertifierData) private certifiers;

    // Mapping of token ID to sale info
    mapping(uint256 => SaleInfo) public tokenSales;

    // Events
    event CertifierAdded(address indexed certifierAddress, string certifierName);
    event CertifierRemoved(address indexed certifierAddress);
    event ChangedCommissionRecipient(address indexed oldCommissionRecipient, address indexed newCommissionReceiver);
    event NFTMinted(address indexed recipient, uint256 indexed tokenId, string tokenURI);
    event NFTListedForSale(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 salePrice);

    constructor(address brandAddress, string memory brandName, string memory collectionName, string memory symbol) 
        ERC721(collectionName, symbol) {
        transferOwnership(brandAddress);
        commissionRecipient = msg.sender; // Set recipient to be NFTime address
        addCertifier(brandAddress, brandName); // Brand address is set as certifier as well so that it can mint too
    }


    // --------------------
    // Methods - only owner
    // --------------------

    function addCertifier(address certifierAddress, string memory certifierName) public onlyOwner {
        certifiers[certifierAddress].name = certifierName;
        certifiers[certifierAddress].isActive = true;
        emit CertifierAdded(certifierAddress, certifierName);
    }

    function removeCertifier(address certifierAddress) external onlyOwner {
        delete certifiers[certifierAddress];
        emit CertifierRemoved(certifierAddress);
    }


    // -----------------------------------
    // Methods - only commission recipient
    // -----------------------------------

    function setCommissionRecipient(address recipient) external {
        require(msg.sender == commissionRecipient, "Only the commission recipient can transfer this role");
        address oldCommissionRecipient = commissionRecipient;
        commissionRecipient = recipient;
        emit ChangedCommissionRecipient(oldCommissionRecipient, recipient);
    }


    // -------------------------
    // Methods - only certifiers
    // -------------------------

    function getCommissionValue() returns (uint256) {
        return 1510802235987309200000000000000;
    }

    function mintNFT(address recipient, string memory tokenURI) external payable returns (uint256) {
        require(certifiers[msg.sender].isActive, "Only active 'certifiers' can perform this operation");
        uint256 commissionValue = getCommissionValue();
        require(msg.value >= commissionValue, "Not enough commission sent");
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(recipient, newItemId);
        _setTokenURI(newItemId, tokenURI);
        emit NFTMinted(recipient, newItemId, tokenURI);
        payable(commissionRecipient).transfer(commissionValue);
        return newItemId;
    }


    // ------------------
    // Methods - everyone
    // ------------------

    function listNFTForSale(uint256 tokenId, uint256 price) external {
        address seller = msg.sender;
        require(ownerOf(tokenId) == seller, "You can only list your own token");
        require(price > 0, "Price must be greater than zero");

        tokenSales[tokenId] = SaleInfo(price, seller);

        emit NFTListedForSale(seller, tokenId, price);
    }

    function buyNFT(uint256 tokenId) external payable {
        SaleInfo memory sale = tokenSales[tokenId];
        require(sale.price > 0, "This token is not for sale");
        require(msg.value == sale.price, "Incorrect sale price sent");

        address seller = sale.seller;
        uint256 salePrice = sale.price;

        // Calculate commission
        uint256 commission = salePrice / 100 * 5;
        uint256 sellerProceeds = salePrice - commission;

        // Handle payment
        payable(commissionRecipient).transfer(commission);
        payable(seller).transfer(sellerProceeds);

        // Transfer the token to the buyer
        _transfer(seller, msg.sender, tokenId);

        // Clean up the sale info
        delete tokenSales[tokenId];

        emit NFTSold(seller, msg.sender, tokenId, salePrice);
    }


    // ---------------------
    // Overrides (necessary)
    // ---------------------

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}