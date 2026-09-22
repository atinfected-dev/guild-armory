--[[----------------------------------------------------------------------------
    Data/RaidHistory — Raidabende aus Warcraft Logs.

    ERZEUGT, NICHT VON HAND GEPFLEGT.  npm run raids

    Diese Fassung ist der LEERE ANFANGSZUSTAND. Sie steht hier, damit die
    .toc eine Datei findet, bevor das Werkzeug zum ersten Mal gelaufen ist —
    ein fehlender Eintrag in der .toc ist ein Ladefehler, eine leere Tabelle
    nicht.

    Alles, was hier spaeter steht, ist BEOBACHTET, nicht gemessen: Es stammt
    aus hochgeladenen Logs, nicht aus dem, was dieser Client gesehen hat. Wer
    einen Abend nicht hochgeladen hat, steht nicht drin — und eine Rangliste,
    die das verschweigt, belohnt das Hochladen statt das Raiden.
------------------------------------------------------------------------------]]

local _, GA = ...

GA.Data.RaidHistory = {
    generated = 0,
    reports = 0,
    source = "Warcraft Logs",
    nights = {},
    firstKills = {},
}
