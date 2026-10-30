CREATE TABLE meetings(id TEXT PRIMARY KEY NOT NULL,title TEXT NOT NULL,created_at REAL NOT NULL,
                    recording_state TEXT NOT NULL CHECK(recording_state IN ('recording','completed','interrupted','recovered','failed')),
                    captured_sample_count INTEGER NOT NULL CHECK(captured_sample_count>=0));
                CREATE INDEX meeting_history ON meetings(created_at DESC,id);
                CREATE TABLE transcript_segments(id TEXT PRIMARY KEY NOT NULL,meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL CHECK(sequence>=0),start_sample INTEGER NOT NULL CHECK(start_sample>=0),
                    end_sample INTEGER NOT NULL CHECK(end_sample>=start_sample),text TEXT NOT NULL,model_revision TEXT NOT NULL,
                    UNIQUE(meeting_id,sequence));
                CREATE TABLE manual_notes(meeting_id TEXT PRIMARY KEY NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                    text TEXT NOT NULL,edit_revision INTEGER NOT NULL,modified_at REAL NOT NULL);
                CREATE TABLE generated_documents(id TEXT PRIMARY KEY NOT NULL,meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK(kind IN ('summary','question_answer')),original_json BLOB NOT NULL,question TEXT,
                    edited_text TEXT NOT NULL,edit_revision INTEGER NOT NULL,model_revision TEXT NOT NULL,prompt_version TEXT NOT NULL,
                    created_at REAL NOT NULL,modified_at REAL NOT NULL);
                CREATE INDEX document_history ON generated_documents(meeting_id,created_at DESC,id);
                CREATE TABLE meeting_speech_model_pins(meeting_id TEXT PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,selection_json TEXT NOT NULL);
                CREATE TABLE preferred_summaries(meeting_id TEXT PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,
                    document_id TEXT NOT NULL REFERENCES generated_documents(id) ON DELETE CASCADE);
                CREATE TABLE sync_receipts(transfer_id TEXT PRIMARY KEY NOT NULL,source_id TEXT NOT NULL,digest TEXT NOT NULL,committed_at REAL NOT NULL);
                CREATE VIRTUAL TABLE transcript_fts USING fts5(text,content='transcript_segments',content_rowid='rowid',tokenize='unicode61 remove_diacritics 2');
                CREATE TRIGGER transcript_insert AFTER INSERT ON transcript_segments BEGIN INSERT INTO transcript_fts(rowid,text) VALUES(new.rowid,new.text); END;
                CREATE TRIGGER transcript_delete AFTER DELETE ON transcript_segments BEGIN INSERT INTO transcript_fts(transcript_fts,rowid,text) VALUES('delete',old.rowid,old.text); END;
                PRAGMA user_version=1;