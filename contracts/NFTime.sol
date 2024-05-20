// SPDX-License-Identifier: UNLICENSED 
// MyContract.sol
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Aspettare di usarli prima di mettere: ERC721URIStorage, Ownable
contract NFTime is ERC721{
    // metodi di pagamento (una tantum, periodico, percentuali sulle transazioni)

    // TODO:
    // Logica minting e trasferimento NFTs
    // Gestione dei ruoli (come viene inserito un brand piuttosto che come viene "eletto" un certificatore):
        // WAIT Funzione per aggiungere un certificatore (es. i brand possono aggiungerli -> penso alla logica (vedere cosa dicono Simo e Mario))
    // Capire come vengono gestiti gli NFT nei progetti gia esistenti e di successo
    // [NOT THAT IMPORTANT] Studiare ereditarieta tra struct per risparmiare memoria ed ottimizzare
    // Rivalutare tipi dato usati


    // ------------
    // Data Structs
    // ------------

    struct CertifierData
    {
        string name;
        bool isActive;
    }

    struct BrandData
    {
        string name;
        bool isActive;
    }

    struct AssociationData
    {
        // TO DEFINE: campi in base al metodo di pagamento e alla logica che dobbiamo implementare
        //string firstAssociationDate;
        //string subExpirationDate;
        //uint paymentMethod;
        //uint paymentQuota;
        //uint percentageOnCertifications;
        bool status;
    }

    // --------------------------
    // Global / private variables
    // --------------------------
    
    // Contract owner address
    address private contractOwner;
    // List of brands
    mapping(address => BrandData) private brands;
    // List of certifiers
    mapping(address => CertifierData) private certifiers;
    // Dall'address del brand si accede agli address dei certificatori e ai dati sulle loro associazioni.
    mapping(address => mapping(address => AssociationData)) private associations;  //E.g. associations[addressBrand][addressCertifier].status;
    
    // ---------
    // Modifiers
    // ---------
    
    // Modifier to restrict access to the owner
    modifier onlyOwner()
    {
        require(msg.sender == contractOwner, "Only the contract owner can perform this operation");
        _;
    }

    modifier onlyBrands()
    {
        require(brands[msg.sender].isActive, "Only 'brands' can perform this operation");
        _;
    }

    modifier onlyCertifiers()
    {
        require(certifiers[msg.sender].isActive || brands[msg.sender].isActive, "Only 'certifiers' can perform this operation");
        _;
    }
    

    // --------------------
    // constructor
    // --------------------
    
    constructor() ERC721("NFTime", "WTC")
    { 
        contractOwner = msg.sender;
    }

    // --------------------
    // Methods - only owner
    // --------------------

    /* Veniamo pagati fuori dalla blockchain e poi chiamiamo il metodo (per ora) /
    (alternativa da sviluppare in futuro) Creare un secondo SC che gestisce questo genere di pagamenti
                                          Ha i diritti di chiamare i metodi necessari su questo SC
                                          In questo modo potremmo gestire i pagamenti anche direttamente in ETH
                                          (Bisogna comunque pensare bene alla logica con il quale (e se) sviluppare il secondo SC) 
    */
    addBrand(address brandAddress, string memory name) public onlyOwner
    {
        BrandData memory brand = BrandData(name, true) // name, isActive
        brands[brandAddress] = brand;
    }
    
    // IN CASO DI ERRORI DI INSERIMENTO BRAND/CERTIFICATORI? DA CONSIDERARE (per ora basta richiamare il metodo con i parametri giusti)
    // Dopo incontro con Simo e Mario, programmare la disabilitazione dei brand/certificatori

    // ---------------------
    // Methods - only brands
    // ---------------------
    
    addCertifier(address certifierAddress, string memory name) public onlyBrands
    {
        // TODO: Pensare a relativi controlli necessari

        // controllo esistenza certifier
        if(!certifiers[certifierAddress].isActive)
        {
            CertifierData memory certifier = CertifierData(name, true) // name, isActive
            certifiers[certifierAddress] = certifier;
        }

        AssociationData memory association = AssociationData(true) // status
        associations[msg.sender][certifierAddress] = association;
    }
}