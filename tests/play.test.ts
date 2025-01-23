import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("play contract", () => {
    it("allows users to start a game session", () => {
        const startGameCall = simnet.callPublicFn(
            "play",
            "start-game-session",
            [],
            wallet1
        );
        expect(startGameCall.result).toBeOk(Cl.bool(true));
        
        const getSessionsCall = simnet.callReadOnlyFn(
            "play",
            "get-player-sessions",
            [Cl.principal(wallet1)],
            wallet1
        );
        expect(getSessionsCall.result).toBeOk(Cl.uint(1));
    });

    it("returns correct play price", () => {
        const getPriceCall = simnet.callReadOnlyFn(
            "play",
            "get-play-price",
            [],
            wallet1
        );
        expect(getPriceCall.result).toBeOk(Cl.uint(1000000)); // 1 STX
    });

    it("only allows contract owner to set developer address", () => {
        const setDeveloperCall = simnet.callPublicFn(
            "play",
            "set-developer-address",
            [Cl.principal(wallet1)],
            wallet1
        );
        expect(setDeveloperCall.result).toBeErr(Cl.bool(true));
    });
});
