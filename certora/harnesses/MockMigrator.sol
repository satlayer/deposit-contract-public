contract MockMigrator {
    function migrate(
        address _user,
        string calldata _destinationAddress, 
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external {}
}