# Import '.env' file
-include .env

# Install foundry modules
install:
	forge install foundry-rs/forge-std@v1.9.7 && \
	forge install eth-infinitism/account-abstraction@v0.7.0 && \
	forge install OpenZeppelin/openzeppelin-contracts@v5.3.0 && \
	forge install Cyfrin/foundry-era-contracts@0.0.3

# Remove foundry modules
remove:
	rm -rf lib

format:
	forge fmt

# Build the project
# ; is to write the command in the same line
build :; forge fmt && forge build
build-force :; forge build --force
build-zksync:
	forge fmt && forge build --zksync

test-simple:
	forge test --match-path test/ethereum/*
test-verbose:
	forge test -vvvv --match-path test/ethereum/*

test-zksync:
	forge test --zksync --via-ir --system-mode=true --match-path test/zkSync/*
test-zksync-verbose:
	forge test --zksync --via-ir --system-mode=true --match-path test/zkSync/* -vvvv

coverage:
	forge coverage
coverage-debug:
	forge coverage --report debug > coverage-report.txt

anvil :; anvil

deploy-anvil:
	forge script script/DeployMerkleAirdrop.s.sol:MerkleAirdropDeployer \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
	--broadcast
