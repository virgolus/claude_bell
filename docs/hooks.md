# Claude Code Hooks — Gestiti da Claude Bell

## Panoramica

Claude Code espone **17 hook event types**. Claude Bell ne gestisce 5 (con endpoint HTTP dedicati) + intercetta le notifiche rilevanti.

Ogni tipo di notifica è definito in `NotificationMeta` (`Sources/Models/NotificationEntry.swift`) che centralizza: titolo, icone, colore, testo notifica nativa, flag `isPassive` e `deduplicate`.

## Hook gestiti

### 1. `PermissionRequest` — Bloccante

**Endpoint:** `POST /hooks/permission-request`
**Quando:** Claude Code sta per eseguire un tool che richiede permesso (Bash, Write, Edit, ecc.)
**Comportamento:** La connessione HTTP resta aperta fino a quando l'utente risponde Allow/Deny nell'app. La risposta JSON viene inviata a Claude Code che procede o annulla.

**Payload ricevuto:**
```json
{
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /tmp/cache" },
  "transcript_path": "/path/to/transcript.jsonl",
  "hook_event_name": "PermissionRequest",
  "permission_mode": "default"
}
```

**Risposta (Allow):**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "allow" }
  }
}
```

**Risposta (Deny):**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "deny" }
  }
}
```

**Timeout:** 5 minuti. Se l'utente non risponde, viene automaticamente negato.

---

### 2. `Notification` — Fire-and-forget

**Endpoint:** `POST /hooks/notification`
**Quando:** Claude Code invia una notifica.
**Matcher configurato:** `permission_prompt|idle_prompt|elicitation_dialog`

**Tipi di notifica gestiti:**

| Tipo | Descrizione | Azione nell'app |
|------|-------------|-----------------|
| `permission_prompt` | Claude sta mostrando un prompt di permesso nel terminale | Mostra notifica con contesto dal transcript |
| `idle_prompt` | Claude è in attesa di input (idle da 60+ secondi) | Mostra notifica + campo testo per risposta |
| `elicitation_dialog` | Claude sta ponendo una domanda interattiva (AskUserQuestion) | Mostra domanda con opzioni cliccabili |

**Filtro messaggi generici:** I messaggi come "Claude is waiting for your input", "Claude needs your permission to use X" vengono filtrati per evitare testo ridondante — il contesto viene mostrato dal transcript.

**Per AskUserQuestion:** le opzioni non sono nel payload della notifica. Claude Bell legge il transcript JSONL per trovare l'ultima `AskUserQuestion` e ne estrae domande e opzioni. Supporta:
- Domande singole e multiple
- Single select (click → invio immediato)
- Multi select (checkbox + Submit)

**Risposta:** Nessuna (fire-and-forget). L'utente può rispondere via AppleScript a Terminal.app o aprire il terminale.

---

### 3. `Stop` — Fire-and-forget

**Endpoint:** `POST /hooks/stop`
**Quando:** Claude Code ha finito di rispondere (il task è completato).
**Comportamento:**
- Mostra una notifica "Task Completed" con l'ultimo messaggio di Claude
- Deduplica: una sola notifica per sessione
- Auto-dismiss: rimuove eventuali notifiche interattive stale della stessa sessione
- Notifica nativa macOS

**Payload ricevuto:**
```json
{
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "hook_event_name": "Stop",
  "transcript_path": "/path/to/transcript.jsonl",
  "last_assistant_message": "Done! I've implemented..."
}
```

---

### 4. `PostToolUseFailure` — Fire-and-forget

**Endpoint:** `POST /hooks/post-tool-use-failure`
**Quando:** Un tool di Claude Code fallisce con errore.
**Comportamento:** Mostra una notifica con il nome del tool e il messaggio di errore. Deduplica per sessione.

**Payload ricevuto:**
```json
{
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "hook_event_name": "PostToolUseFailure",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" },
  "error": "Command failed with exit code 1",
  "transcript_path": "/path/to/transcript.jsonl"
}
```

---

### 5. `SessionEnd` — Fire-and-forget

**Endpoint:** `POST /hooks/session-end`
**Quando:** Una sessione di Claude Code termina.
**Comportamento:**
- Rimuove la sessione dal tracking
- Auto-dismiss: rimuove eventuali notifiche interattive stale della stessa sessione
- Mostra notifica "Session Ended"

**Payload ricevuto:**
```json
{
  "session_id": "abc123",
  "cwd": "/path/to/project",
  "hook_event_name": "SessionEnd",
  "transcript_path": "/path/to/transcript.jsonl"
}
```

---

## Auto-dismiss delle notifiche stale

Quando arriva un evento passivo (`Stop`, `SessionEnd`, `PostToolUseFailure`) per una sessione, tutte le notifiche interattive (`permission_prompt`, `idle_prompt`, `elicitation_dialog`) della stessa sessione vengono automaticamente rimosse. Questo gestisce il caso in cui l'utente risponde direttamente nel terminale: Claude procede, manda `Stop`, e Claude Bell pulisce le notifiche ora non più valide.

---

## Hook NON gestiti

Claude Code espone 17 hook events in totale. Quelli non gestiti da Claude Bell:

### Potenzialmente utili

| Hook | Quando | Perché potrebbe servire |
|------|--------|------------------------|
| `PreToolUse` | Prima dell'esecuzione di un tool | Filtrare/modificare comandi prima che vengano eseguiti |
| `PostToolUse` | Dopo l'esecuzione riuscita | Logging, audit trail, notifiche su operazioni specifiche |
| `UserPromptSubmit` | Quando l'utente invia un prompt | Intercettare/validare prompt prima dell'elaborazione |
| `TaskCompleted` | Quando un task viene completato (team) | Tracciare progresso dei task nei team |
| `SubagentStop` | Quando un subagente finisce | Monitorare agenti paralleli |

### Meno rilevanti per Claude Bell

| Hook | Quando | Note |
|------|--------|------|
| `SessionStart` | Inizio sessione | Solo per setup ambiente |
| `SubagentStart` | Avvio subagente | Solo informativo |
| `TeammateIdle` | Teammate idle (team) | Specifico per agent teams |
| `ConfigChange` | Modifica configurazione | Specifico per admin |
| `WorktreeCreate` | Creazione worktree | Specifico per git |
| `WorktreeRemove` | Rimozione worktree | Specifico per git |
| `PreCompact` | Prima della compattazione | Specifico per context management |

---

## Architettura

### NotificationMeta (centralizzato)

Ogni tipo di notifica ha un `NotificationMeta` che definisce:

| Campo | Descrizione |
|-------|-------------|
| `displayTitle` | Titolo mostrato nell'app |
| `icon` / `rowIcon` | SF Symbols per detail view e sidebar |
| `iconColor` | Colore dell'icona (verde per stop, arancione per errori, ecc.) |
| `nativeBody` | Testo della notifica macOS nativa |
| `isPassive` | `true` = nessun input richiesto (dismiss con Enter, no transcript, no campo testo) |
| `deduplicate` | `true` = una sola notifica per sessione/tipo |

### Flusso dati

```
Claude Code → HTTP POST → HookServer.decodeInput()
                              │
                              ├── PermissionRequest: withCheckedContinuation → PendingRequest
                              │                                                     │
                              │                                              Allow/Deny → HTTP Response
                              │
                              └── Fire-and-forget: NotificationEntry → RequestStore
                                                                          │
                                                          ├── deduplicate (se meta.deduplicate)
                                                          ├── auto-dismiss stale (se meta.isPassive)
                                                          └── sendNativeNotification()
```

---

## Configurazione in `~/.claude/settings.json`

```json
{
  "hooks": {
    "PermissionRequest": [{
      "matcher": "",
      "hooks": [{
        "type": "http",
        "url": "http://localhost:19485/hooks/permission-request",
        "timeout": 300
      }]
    }],
    "Notification": [{
      "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
      "hooks": [{
        "type": "http",
        "url": "http://localhost:19485/hooks/notification",
        "timeout": 10
      }]
    }],
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "http",
        "url": "http://localhost:19485/hooks/stop",
        "timeout": 10
      }]
    }],
    "PostToolUseFailure": [{
      "matcher": "",
      "hooks": [{
        "type": "http",
        "url": "http://localhost:19485/hooks/post-tool-use-failure",
        "timeout": 10
      }]
    }],
    "SessionEnd": [{
      "matcher": "",
      "hooks": [{
        "type": "http",
        "url": "http://localhost:19485/hooks/session-end",
        "timeout": 10
      }]
    }]
  }
}
```

## Graceful degradation

- Se Claude Bell non è in esecuzione → le richieste HTTP falliscono → Claude Code mostra i dialoghi normalmente nel terminale
- Se il timeout scade (5 min per PermissionRequest) → il permesso viene negato automaticamente
- Nessun rischio di bloccare Claude Code permanentemente
