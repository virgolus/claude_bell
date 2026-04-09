# ClaudeBell — Funzionalita

## Menu bar

- Icona nella barra dei menu con tre stati: campana (inattiva), campana con badge (elementi in attesa), campana barrata (muto)
- Badge numerico che mostra il conteggio di richieste e notifiche pendenti
- Menu contestuale con click destro: Mute/Unmute, Impostazioni, What's New, Controlla aggiornamenti, About, Esci
- Pannello flottante attivabile con click o shortcut globale

## Hook system

Server HTTP locale su `localhost:19485` che riceve eventi da Claude Code tramite [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks). Sei tipi di hook configurati:

| Hook | Descrizione |
|------|-------------|
| **PermissionRequest** | Richieste di autorizzazione per l'uso di tool |
| **Notification** | Notifiche interattive (permission_prompt, idle_prompt, elicitation_dialog) |
| **PreToolUse** | Tracciamento avanzamento sessione, pulizia notifiche obsolete |
| **PostToolUseFailure** | Errori nell'esecuzione di tool |
| **Stop** | Completamento task o attesa input |
| **SessionEnd** | Terminazione sessione Claude Code |

Endpoint di health check su `GET /health`.

## Gestione permessi

- Approvazione o rifiuto delle richieste di permesso per i tool di Claude Code
- Pulsante "Allow Always" per approvazione permanente (usa permission_suggestions)
- Timeout automatico di 5 minuti per le richieste non gestite
- Auto-deny delle richieste obsolete quando ne arriva una nuova
- Visualizzazione del nome del tool e dei parametri di input
- Icone specifiche per ogni tool (Bash, Edit, Write, Read, Grep, Agent, ecc.)

## Notifiche interattive

- **Permission prompt**: richieste di permesso con contesto dal transcript
- **Idle prompt**: Claude Code e in attesa di input
- **Elicitation dialog**: dialoghi con domande e opzioni
- Supporto per domande a scelta multipla con selezione via tastiera
- Azioni di follow-up contestuali
- Input di testo per risposte libere
- Deduplicazione intelligente: alcune notifiche sostituiscono quelle precedenti della stessa sessione
- Rilevamento automatico: idle_prompt convertito in "stop" se il transcript non mostra domande pendenti

## Tracciamento sessioni

- Elenco delle sessioni Claude Code attive nella sidebar
- Nome sessione personalizzabile (rename)
- Visualizzazione dell'ultimo prompt utente per ogni sessione
- Pulizia automatica delle sessioni inattive (ogni 5 minuti, soglia 30 minuti)
- Rimozione sessione su evento SessionEnd o dismissione manuale

## Integrazione terminale

Supporto per tre applicazioni terminale:

- **Terminal.app** — matching multi-pass (TTY esatto, processo Claude + CWD, fallback)
- **iTerm2** — integrazione nativa via AppleScript
- **Warp** — supporto limitato via paste (Cmd+V)

Funzionalita:
- Focus automatico sulla tab del terminale che esegue Claude Code
- Invio testo al terminale (clipboard paste + Enter)
- Risoluzione TTY tramite lsof + ps
- Supporto invio in due passaggi (numero opzione + testo completo)

## Shortcut globale

- Scorciatoia da tastiera per aprire/chiudere il pannello (default: Cmd+Shift+B)
- Personalizzabile con qualsiasi combinazione di tasti (Cmd/Shift/Opt/Ctrl + tasto)
- Implementazione via Carbon RegisterEventHotKey (non richiede permessi Accessibilita)
- Configurabile dalle Impostazioni > Generale

## Audio e notifiche

- 13 suoni disponibili: Purr, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Sosumi, Submarine, Tink
- Suoni differenziati per richieste di permesso e notifiche
- Toggle mute globale (persistente)
- Notifiche native macOS (banner + suono di sistema)
- Toggle per abilitare/disabilitare le notifiche di errore tool
- Toggle per abilitare/disabilitare le notifiche native macOS
- Anteprima suono nelle impostazioni

## Aggiornamento automatico

- Verifica automatica aggiornamenti al lancio e ogni 30 minuti
- Controllo manuale disponibile dal menu contestuale
- Download e installazione in-app (scarica zip, sostituisce il bundle, riavvio automatico)
- Banner di notifica quando un aggiornamento e disponibile
- Memorizzazione degli aggiornamenti gia ignorati dall'utente

## Personalizzazione aspetto

- **Posizione pannello**: Menu Bar, Sinistra, Destra, Fullscreen
- **Larghezza pannello**: regolabile da 500 a 1400 punti (default 900)
- **Tema**: Sistema, Chiaro, Scuro
- **Colore sfondo**: selettore colore con supporto hex
- **Colore testo**: selettore colore con supporto hex
- **Font**: 8 opzioni tra cui il default di sistema
- Anteprima live delle modifiche
- Reset individuale per ogni personalizzazione
- Tutte le preferenze persistono tra i riavvii

## Status line

- Script bash installabile che mostra informazioni nella status line di Claude Code:
  - Nome del modello corrente
  - Directory corrente (basename)
  - Branch git (se in un repository)
  - Utilizzo context window (0-100%, colore: verde <70%, giallo <90%, rosso >=90%)
  - Durata sessione (minuti e secondi)
- Gestibile dalle Impostazioni > Varie

## Auto Mode

- Abilita/disabilita l'approvazione automatica dei tool basata su classificatore AI
- Modifica `~/.claude/settings.local.json`
- Toggle nelle Impostazioni > Generale
- Richiede riavvio della sessione Claude Code per applicare

## Contesto transcript

- Visualizzatore del contesto conversazionale per ogni notifica/richiesta
- Parsing dei file transcript JSONL di Claude Code
- Estrazione degli ultimi messaggi utente/assistente
- Visualizzazione dei tool usati con riepilogo dei parametri
- Rilevamento domande pendenti (incluse domande a scelta multipla)

## Rendering Markdown

- Supporto per intestazioni (livelli 1-4)
- **Grassetto**, *corsivo*, ***grassetto corsivo***
- `Codice inline` e blocchi di codice con sintassi
- Tabelle (delimitatore pipe)
- Liste ordinate e non ordinate con nesting
- Divisori orizzontali
- Selezione testo abilitata
- Font monospace per il codice

## Setup guidato

- Overlay di primo avvio se gli hook non sono installati
- Installazione hook con un click
- Spiegazione Auto Mode
- Guida configurazione Status Line
- Tracciamento stato completamento

## Navigazione da tastiera

- Esc per chiudere il pannello
- Cmd+, per aprire le impostazioni
- Tab/Frecce per navigare tra i pulsanti nel dettaglio richiesta
- Enter per attivare il pulsante con focus
- Selezione opzioni domande via tastiera

## Impostazioni

Quattro tab:

- **Generale**: stato hook, toggle Auto Mode, registrazione shortcut globale
- **Notifiche**: scelta suono, anteprima, mute, toggle errori tool, toggle notifiche native
- **Aspetto**: posizione pannello, larghezza, tema, colori, font, anteprima live
- **Varie**: installazione status line
