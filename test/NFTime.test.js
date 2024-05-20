const NFTime = artifacts.require("NFTime");
let nftime;

before(async() => {
    nftime = await NFTime.new();
})

contract("MyToken", (accounts) => {

    let contract;

    before(async() => {

        contract = await NFTime.deployed();

    });

    describe("nftime", async() => {

        it("deploys", async() => {
            const address = contract.address;
            assert.notEqual(address, null);
        })
    })
})