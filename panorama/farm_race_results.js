"use strict";

function ResultName(result) {
    return result.playerId >= 0 ? Players.GetPlayerName(result.playerId) || result.name : result.name;
}

var livePanel = $("#LiveLeaderboard");
var finalPanel = $("#FarmResults");
var liveRows = $("#LiveRows");
var finalRows = $("#ResultsRows");
livePanel.visible = false;
finalPanel.visible = false;

function RenderRows(container, results, live) {
    for (var place = 1; place <= 5; place++) {
        var result = results[place];
        var row = container.GetChild(place - 1);
        if (!row) {
            row = $.CreatePanel("Panel", container, "");
            row.AddClass(live ? "LiveRow" : "ResultRow");
            $.CreatePanel("Label", row, "").AddClass(live ? "LivePlace" : "Place");
            $.CreatePanel("Label", row, "").AddClass("Player");
            if (!live) {
                for (var category = 0; category < 3; category++) {
                    $.CreatePanel("Label", row, "").AddClass("FarmPoints");
                }
            }
            $.CreatePanel("Label", row, "").AddClass(live ? "LiveScore" : "Score");
        }
        row.SetHasClass("WinningRow", place === 1 && (!live || result.score > 0));
        row.SetHasClass("IsLocalPlayer", live && result.playerId === Game.GetLocalPlayerID());
        row.GetChild(0).text = String(place);
        row.GetChild(1).text = ResultName(result);
        if (live) {
            row.GetChild(2).text = String(result.score);
        } else {
            var farm = result.farm || {};
            row.GetChild(2).text = String(farm.lane || 0);
            row.GetChild(3).text = String(farm.forest || 0);
            row.GetChild(4).text = String(farm.gold || 0);
            row.GetChild(5).text = String(result.score);
        }
    }
}

function ShowStandings(standings) {
    if (!standings || !standings.rows) return;
    if (Number(standings.finished) === 0) {
        RenderRows(liveRows, standings.rows, true);
        livePanel.AddClass("LiveVisible");
        livePanel.visible = true;
        return;
    }

    livePanel.visible = false;
    livePanel.RemoveClass("LiveVisible");

    var winner = standings.rows[1];
    var name = ResultName(winner);
    $("#ResultsTitle").text = $.Localize("#farm_race_victory_prefix") + " " + name;
    $("#WinnerName").text = name;
    $("#WinnerScore").text = String(winner.score);
    RenderRows(finalRows, standings.rows, false);
    finalPanel.style.width = (Game.GetScreenWidth() / (finalPanel.actualuiscale_x || 1)) + "px";
    finalPanel.style.height = (Game.GetScreenHeight() / (finalPanel.actualuiscale_y || 1)) + "px";
    finalPanel.AddClass("ResultsVisible");
    finalPanel.visible = true;
}

CustomNetTables.SubscribeNetTableListener("farm_race", function (_, key, standings) {
    if (key === "standings") ShowStandings(standings);
});
ShowStandings(CustomNetTables.GetTableValue("farm_race", "standings"));
