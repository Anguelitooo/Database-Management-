-- =====================================================================
-- Database Management (7000DMD_23) — Movie Box-Office Project
-- schema.sql — table definitions matching the ERD in
-- DMD_Research_Design_Draft.docx (Figure 1)
--
-- v3.2: resolves the two "decision needed" items v3.1 had left open.
-- (1) possessive_pronoun_pct renamed to personal_pronoun_pct (mapped to
-- LIWC's 'ppron'). Checked directly against the LIWC2015 Development
-- Manual (LIWC2015_LanguageManual.pdf): its full category table lists
-- total pronouns, personal pronouns (ppron) with four subtypes, and
-- impersonal pronouns (ipron) — no possessive-pronoun category exists
-- anywhere in LIWC2015, in this data or in the dictionary itself, so
-- 'ppron' was never a guess standing in for something better; it is the
-- correct name for what this column actually measures. The original
-- name most likely confused "personal" with "possessive". Also
-- confirmed this column is not referenced by any hypothesis text,
-- query, or Python function, so nothing downstream depended on the old
-- name. (2) director/cast/studio mojibake fixed — see the people and
-- studios table comments below.
--
-- v3.1: fixes a real bug found while building build_tables.py: LIWC's
-- 'pronoun' field is a percentage of words, like the other LIWC
-- columns, not a raw count, but pronoun_count was typed INT in both
-- review tables. Loading a real value (e.g. 17.7) into an INT column
-- fails on import. Widened to NUMERIC(5,2) to match its neighbours.
--
-- v3: adds people, movie_credits, studios and movie_studios. This is a
-- fail-safe extension added at the professor's request following the
-- team's approval of the core ERD, so the schema can support future
-- research beyond the review-characteristics angle this project tests
-- (H1-H5 and their sub-questions do not require any of these four
-- tables). people holds one row per individual credited on a film,
-- whether as director or cast, rather than splitting the two into
-- separate tables, since a person credited in both roles across
-- different films should be represented once; movie_credits is the
-- bridge, tagged with credit_type so a further credit type (writer,
-- producer) is a data change rather than a schema change later.
-- studios follows the same normalisation logic already used for
-- genres, since 1.7% of populated studio values in the source data
-- list more than one studio.
--
-- v2: adds a normalised genres entity (movies.genre in the source data
-- is a comma-separated list, so it is split into genres + movie_genres
-- rather than kept as a single denormalised text column) and extends
-- consumer_reviews / expert_reviews with LIWC2015's four summary
-- dimensions (Analytic, Clout, Authentic, Tone) plus certainty language
-- (certain, tentative), per the revised H3 in the research design draft.
--
-- Code of conduct reminder (per the module syllabus): credit any
-- adapted code inline like a citation, and mark who wrote each block.
-- Written by: [your name]
-- =====================================================================

-- Drop in dependency order so this script is safely re-runnable while
-- you iterate on the design. Bridge tables first, then the entities
-- they reference, then movies last.
DROP TABLE IF EXISTS movie_credits;
DROP TABLE IF EXISTS movie_studios;
DROP TABLE IF EXISTS movie_genres;
DROP TABLE IF EXISTS people;
DROP TABLE IF EXISTS studios;
DROP TABLE IF EXISTS genres;
DROP TABLE IF EXISTS consumer_reviews;
DROP TABLE IF EXISTS expert_reviews;
DROP TABLE IF EXISTS movies;

-- ---------------------------------------------------------------------
-- movies — one row per film (from MetaClean + sales data)
-- Strong entity; primary key movie_id.
-- ---------------------------------------------------------------------
CREATE TABLE movies (
    movie_id            SERIAL PRIMARY KEY,
    title                VARCHAR(255) NOT NULL,
    metacritic_url       VARCHAR(500) UNIQUE NOT NULL,
    production_budget    NUMERIC(14, 2),      -- USD
    box_office           NUMERIC(14, 2),      -- USD
    runtime_minutes      INT
);

-- ---------------------------------------------------------------------
-- genres / movie_genres — normalises the comma-separated genre list
-- found in MetaClean into a proper many-to-many relationship. A film
-- can belong to more than one genre, so a single text column on movies
-- cannot be filtered, grouped or joined on cleanly; movie_genres holds
-- no attributes beyond the two foreign keys that define the
-- relationship (see Section 3 of the research design draft).
-- ---------------------------------------------------------------------
CREATE TABLE genres (
    genre_id             SERIAL PRIMARY KEY,
    genre_name           VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE movie_genres (
    movie_id              INT NOT NULL REFERENCES movies(movie_id),
    genre_id              INT NOT NULL REFERENCES genres(genre_id),
    PRIMARY KEY (movie_id, genre_id)  -- composite primary key: movie_id and genre_id together, not a separate id column
);

-- ---------------------------------------------------------------------
-- people / movie_credits — one row per individual credited on a film,
-- as director and/or cast, plus the bridge that links movies to them.
-- Kept as a single "people" entity rather than separate "directors" and
-- "cast_members" tables so a person credited in both roles (e.g. an
-- actor-director) is represented once, and so a future credit type can
-- be added without a new table.
--
-- A naive comma-split on names fragments name suffixes into a false
-- extra credit (confirmed: the single director value "Michael Landon,
-- Jr." would split into two rows, "Michael Landon" and "Jr.", under
-- the same comma-split logic used for genre); a suffix-aware parser
-- handles that.
--
-- The source cast/director columns also carried UTF-8 mojibake
-- (correct UTF-8 bytes previously decoded as Latin-1, e.g. "KormÃ¡kur"
-- for "Kormákur"): 522 of 11,350 director credits and 1,921 of 48,295
-- cast credits, checked directly against metaClean43Brightspace.xlsx.
-- Reversed with a single encode('latin1').decode('utf-8') pass in
-- build_tables.py, verified against known real names decoding
-- correctly (e.g. Baltasar Kormákur, Alejandro González Iñárritu,
-- Michael Peña, Nacho Cerdà). Ran end to end against the real file:
-- this resolves all 522 director credits and all but 1 of the 1,921
-- cast credits; the single remainder ("Zsolt PÃ") is a name truncated
-- mid-character in the source file itself — a genuine data defect, not
-- an encoding bug — and is left unfixed rather than guessed at.
--
-- Checked directly whether this fix actually merges any duplicate
-- person_id rows in this dataset: it does not — every mojibake-form
-- name appears ONLY in corrupted form throughout the file, never
-- spelled correctly elsewhere, so no two rows for the same real person
-- currently collapse into one (people.csv has 30,314 rows both before
-- and after the fix). The fix is still required for two independent
-- reasons: the uncorrected garbled text would otherwise sit in the
-- final people table as delivered, and it removes the latent identity
-- risk the original schema comment flagged, which would only need to
-- be re-checked if this dataset is ever extended with new credits.
-- person_name is now declared UNIQUE.
-- ---------------------------------------------------------------------
CREATE TABLE people (
    person_id      SERIAL PRIMARY KEY,
    person_name    VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE movie_credits (
    movie_id       INT NOT NULL REFERENCES movies(movie_id),
    person_id      INT NOT NULL REFERENCES people(person_id),
    credit_type    VARCHAR(20) NOT NULL CHECK (credit_type IN ('director', 'cast')),
    PRIMARY KEY (movie_id, person_id, credit_type)  -- composite primary key: all three columns together
);

-- ---------------------------------------------------------------------
-- studios / movie_studios — normalises the studio field the same way
-- genre was normalised. Co-productions are real but rare in this data
-- (1.7% of populated studio values, about 192 films, list more than
-- one studio), so a single denormalised column would still lose data
-- for those films. studio also carried the same UTF-8 mojibake as
-- director/cast (26 rows); fixed the same way, studio_name is now
-- declared UNIQUE.
-- ---------------------------------------------------------------------
CREATE TABLE studios (
    studio_id      SERIAL PRIMARY KEY,
    studio_name    VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE movie_studios (
    movie_id       INT NOT NULL REFERENCES movies(movie_id),
    studio_id      INT NOT NULL REFERENCES studios(studio_id),
    PRIMARY KEY (movie_id, studio_id)  -- composite primary key: movie_id and studio_id together, not a separate id column
);

-- ---------------------------------------------------------------------
-- consumer_reviews — many-to-one with movies (from consumer review data)
-- Includes engagement fields (thumbs_up / total_thumbs) that expert
-- reviews do not have — this is why the two review types are kept in
-- separate tables rather than one "reviews" table with a type flag.
--
-- analytic / clout / authentic / tone are LIWC2015's four summary
-- dimensions (0-100 composite scores, not percentages); certain_pct and
-- tentative_pct are ordinary LIWC category scores, in percent of words,
-- like positive_emotion_pct and negative_emotion_pct already here.
-- ---------------------------------------------------------------------
CREATE TABLE consumer_reviews (
    review_id               SERIAL PRIMARY KEY,
    movie_id                INT NOT NULL REFERENCES movies(movie_id),
    review_text              TEXT,
    review_score              NUMERIC(5, 2),
    thumbs_up                 INT,
    total_thumbs               INT,
    word_count                  INT,
    words_per_sentence           NUMERIC(6, 2),
    pronoun_count                 NUMERIC(5, 2),  -- LIWC's 'pronoun' is a % of words, not a raw count; was wrongly typed INT
    personal_pronoun_pct           NUMERIC(5, 2),  -- LIWC's 'ppron'; renamed from possessive_pronoun_pct (v3.2) — see header note, no possessive-pronoun category exists in LIWC2015
    positive_emotion_pct            NUMERIC(5, 2),
    negative_emotion_pct             NUMERIC(5, 2),
    analytic                          NUMERIC(5, 2),
    clout                               NUMERIC(5, 2),
    authentic                            NUMERIC(5, 2),
    tone                                  NUMERIC(5, 2),
    certain_pct                            NUMERIC(5, 2),
    tentative_pct                           NUMERIC(5, 2)
);

-- ---------------------------------------------------------------------
-- expert_reviews — many-to-one with movies (from expert critic data)
-- Same LIWC extension as consumer_reviews, minus the engagement fields.
-- ---------------------------------------------------------------------
CREATE TABLE expert_reviews (
    review_id             SERIAL PRIMARY KEY,
    movie_id              INT NOT NULL REFERENCES movies(movie_id),
    review_text             TEXT,
    review_score              NUMERIC(5, 2),
    word_count                  INT,
    words_per_sentence           NUMERIC(6, 2),
    pronoun_count                 NUMERIC(5, 2),  -- LIWC's 'pronoun' is a % of words, not a raw count; was wrongly typed INT
    personal_pronoun_pct           NUMERIC(5, 2),  -- LIWC's 'ppron'; renamed from possessive_pronoun_pct (v3.2) — see header note, no possessive-pronoun category exists in LIWC2015
    positive_emotion_pct            NUMERIC(5, 2),
    negative_emotion_pct             NUMERIC(5, 2),
    analytic                          NUMERIC(5, 2),
    clout                               NUMERIC(5, 2),
    authentic                            NUMERIC(5, 2),
    tone                                  NUMERIC(5, 2),
    certain_pct                            NUMERIC(5, 2),
    tentative_pct                           NUMERIC(5, 2)
);

-- Indexes on the foreign keys: every query joining reviews, genres,
-- credits or studios back to movies filters or joins on these columns.
CREATE INDEX idx_consumer_reviews_movie_id ON consumer_reviews(movie_id);
CREATE INDEX idx_expert_reviews_movie_id ON expert_reviews(movie_id);
CREATE INDEX idx_movie_genres_movie_id ON movie_genres(movie_id);
CREATE INDEX idx_movie_genres_genre_id ON movie_genres(genre_id);
CREATE INDEX idx_movie_credits_movie_id ON movie_credits(movie_id);
CREATE INDEX idx_movie_credits_person_id ON movie_credits(person_id);
CREATE INDEX idx_movie_studios_movie_id ON movie_studios(movie_id);
CREATE INDEX idx_movie_studios_studio_id ON movie_studios(studio_id);

-- Next step: load the CSVs into these nine tables (pgAdmin's
-- Import/Export tool, or \copy in psql). MetaClean + sales data merge
-- into movies; consumer review data loads into consumer_reviews;
-- expert critics data loads into expert_reviews. genres, movie_genres,
-- people, movie_credits, studios and movie_studios are not provided as
-- separate source files — split them out of MetaClean's genre, cast,
-- director and studio columns before import (see README.md for the
-- genre-splitting snippet and the required suffix-aware parsing step
-- for cast/director).
