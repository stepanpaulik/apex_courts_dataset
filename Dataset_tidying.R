xfun::pkg_attach2("udpipe","tidyverse", "RMySQL", "lubridate", "utf8", "uchardet")
# Load data
load("data/US_texts.RData")
load("data/US_metadata.RData")
load("models/US_UDmodel.RData")

# Save data
save(data_metadata, file = "data/US_metadata.RData")
save(data_texts, file = "data/US_texts.RData")
save(data_ud, file = "models/US_UDmodel.RData")

distinct <- data_metadata %>% filter(year_cc > 2003) %>% n_distinct()

# Clean useless columns and rename
# data_metadata <- data_metadata %>% subset(select = -c(2,4,5,8,10,24)) %>% rename(
#   doc_id = identifikator_evropske_judikatury,
#   case_id = spisova_znacka,
#   popular_name = popularni_nazev,
#   date_decision = datum_rozhodnuti,
#   date_submission = datum_podani,
#   type_decision = forma_rozhodnuti,
#   type_proceedings = typ_rizeni,
#   importance = vyznam,
#   applicant = navrhovatel,
#   concerned_body = dotceny_organ,
#   judge_rapporteur = soudce_zpravodaj,
#   disputed_act = napadeny_akt,
#   type_verdict = typ_vyroku,
#   concerned_constitutional_acts = dotcene_ustavni_zakony_a_mezinarodni_smlouvy,
#   concerned_acts = ostatni_dotcene_predpisy,
#   dissenting_opinion = odlisne_stanovisko,
#   subject_proceedings = predmet_rizeni,
#   field_register = vecny_rejstrik,
#   note = poznamka,
#   url_adress = url_adresa
# )

# Clean doc_id
data_metadata$doc_id <- str_replace_all(data_metadata$doc_id ,"\\.", ":")
data_texts$doc_id <- str_replace_all(data_texts$doc_id ,"\\.", ":")
join <- left_join(data_metadata, data_texts)

# Split into texts and metadata
data_texts <- data_metadata %>% subset(select = c(doc_id, decisions_texts))
data_metadata <- data_metadata %>% subset(select = -c(decisions_texts))
data_texts <- data_texts %>% rename(
  texts = decisions_texts
)

# Lubridate the dates -- DON'T MAKE THE SAME MISTAKE WITH y/Y! --
data_metadata$date_decision <- as.Date(data_metadata$date_decision, format = "%d. %m. %Y")
data_metadata$date_submission <- as.Date(data_metadata$date_submission, format = "%d. %m. %Y")
data_metadata$length_proceedings <- interval(data_metadata$date_submission, data_metadata$date_decision) %>% as.numeric('days')

# Text normalization
data_texts$texts <- data_texts$texts %>% utf8_normalize(map_quote = TRUE)

# Add outcome as binary variable
add_outcome <- function(data_metadata, outcome = "vyhov??no") {
  data_metadata$outcome <- ifelse(grepl(outcome, data_metadata$type_verdict), "granted", "rejected")
  return(data_metadata)
}

# Fix and check duplicates
data_texts$doc_id <- make.names(data_texts$doc_id, unique = TRUE)
data_metadata$doc_id <- make.names(data_metadata$doc_id, unique = TRUE)
data_duplicates <- data_texts %>% group_by(doc_id) %>% filter(n()>1)

# Add formation
data_metadata <- data_metadata %>%
  mutate(formation = case_when(
    grepl(":Pl:" , doc_id) ~ "Plenum",
    grepl(":1:US:", doc_id) ~ "First Chamber",
    grepl(":2:US:", doc_id) ~ "Second Chamber",
    grepl(":3:US:", doc_id) ~ "Third Chamber",
    grepl(":4:US:", doc_id) ~ "Fourth Chamber"
  ))

# SQL commmunication
conn <- dbConnect(
  RMySQL::MySQL(),
  dbname = "dataset_apexcourts",
  username = "root",
  password = "4E5ad7d!",
  host = "localhost",
  port = 3306
)

dbWriteTable(
  conn,
  "metadata",
  data_metadata,
  overwrite = TRUE,
  row.names = FALSE
)

dbWriteTable(
  conn,
  "texts",
  data_texts,
  overwrite = TRUE,
  row.names = FALSE
)

data_texts <- dbReadTable(
  con,
  "texts"
)

# Create sample for tagging
# sample <- data_texts %>% left_join(., data_metadata) %>% filter(!is.empty(.$dissenting_opinion)) %>% slice_sample(n = 50) %>% select(doc_id, texts)
# sample2 <- data_texts %>% left_join(., data_metadata) %>% filter() %>% filter(is.empty(.$dissenting_opinion)) %>% slice_sample(n = 50) %>% select(doc_id, texts)
# sample <- rbind(sample, sample2)
# write_csv(sample, "data/sample.csv")





