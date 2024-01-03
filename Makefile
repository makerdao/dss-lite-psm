PATH := ~/.solc-select/artifacts/solc-0.8.16:~/.solc-select/artifacts/solc-0.5.12:~/.solc-select/artifacts:$(PATH)
certora-psm     :; PATH=${PATH} certoraRun certora/DssLitePsm.conf$(if $(rule), --rule $(rule),)
certora-pocket  :; PATH=${PATH} certoraRun certora/DssPocket.conf$(if $(rule), --rule $(rule),)
