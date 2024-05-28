

    // Mapping of token ID to sale info
    mapping(uint256 => SaleInfo) public tokenSales;

    event NFTListedForSale(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 salePrice);


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