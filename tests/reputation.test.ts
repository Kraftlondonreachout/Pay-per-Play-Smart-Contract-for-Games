import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const deployer = accounts.get("deployer")!;

describe("reputation contract", () => {
    it("initializes player reputation correctly", () => {
        const initCall = simnet.callPublicFn(
            "reputation",
            "initialize-player-reputation",
            [],
            wallet1
        );
        expect(initCall.result).toBeOk(Cl.bool(true));
        
        const getReputationCall = simnet.callReadOnlyFn(
            "reputation",
            "get-player-reputation",
            [Cl.principal(wallet1)],
            wallet1
        );
        expect(getReputationCall.result).toBeOk(
            Cl.tuple({
                score: Cl.uint(5000),
                "positive-votes": Cl.uint(0),
                "negative-votes": Cl.uint(0),
                "total-games": Cl.uint(0),
                "reputation-level": Cl.stringAscii("regular")
            })
        );
    });

    it("updates reputation for game performance", () => {
        simnet.callPublicFn("reputation", "initialize-player-reputation", [], wallet1);
        
        const updateCall = simnet.callPublicFn(
            "reputation",
            "update-reputation-for-game",
            [Cl.principal(wallet1), Cl.uint(90), Cl.bool(true)],
            deployer
        );
        expect(updateCall.result).toBeOk(Cl.uint(5075));
    });

    it("allows community voting on reputation", () => {
        simnet.callPublicFn("reputation", "initialize-player-reputation", [], wallet1);
        simnet.callPublicFn("reputation", "initialize-player-reputation", [], wallet2);
        
        simnet.callPublicFn(
            "reputation", 
            "update-reputation-for-game",
            [Cl.principal(wallet1), Cl.uint(100), Cl.bool(true)],
            deployer
        );
        
        const voteCall = simnet.callPublicFn(
            "reputation",
            "vote-on-player-reputation",
            [Cl.principal(wallet2), Cl.bool(true)],
            wallet1
        );
        expect(voteCall.result).toBeOk(Cl.bool(true));
    });

    it("checks reputation access levels", () => {
        simnet.callPublicFn("reputation", "initialize-player-reputation", [], wallet1);
        
        const accessCall = simnet.callReadOnlyFn(
            "reputation",
            "check-reputation-access",
            [Cl.principal(wallet1), Cl.uint(4000)],
            wallet1
        );
        expect(accessCall.result).toBeOk(Cl.bool(true));
    });
});
