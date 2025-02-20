#' Summarise the reviewer's agree/decline ratio based on past invites
#'
#' The function pulls out the agree/decline incidence of all the reviewers
#' based on past invite and calculate the agree percentage of each reviewer.
#' Use \code{tabulate_articles} first to tabulate all the articles in a particular directory
#' and then apply this function.
#'
#' @param articles a tibble summary of articles in the accepted and submissions folder. Output of \code{tabulate_articles()}
#' @importFrom tidyr separate_rows pivot_wider
#' @importFrom stringr str_detect word
#' @importFrom scales label_percent
#' @examples
#' \dontrun{
#' articles <- tabulate_articles()
#' reviewer_summary(articles)
#' }
#' @export
reviewer_summary <- function(articles){
  articles %>%
    dplyr::select(id, reviewers) %>%
    tidyr::unnest(reviewers) %>%
    tidyr::separate_rows(comment, sep = "; ") %>%
    dplyr::filter(stringr::str_detect(comment, "Agreed|Declined")) %>%
    dplyr::mutate(comment = tolower(stringr::word(comment))) %>%
    dplyr::group_by(name, comment) %>%
    dplyr::count() %>%
    dplyr::ungroup() %>%
    tidyr::pivot_wider(names_from = comment, values_from = n, values_fill = 0) %>%
    dplyr::relocate(name, agreed, declined) %>%
    dplyr::mutate(ratio = agreed / (agreed + declined),
                  ratio = scales::label_percent()(ratio))
}

#' @rdname ae_workload
#' @param x a single article, i.e. as.article("Submissions/2020-114")
#' @examples
#' \dontrun{
#' art <- as.article("Submissions/2020-114")
#' get_AE(art)
#' }
#' @export
get_AE <- function(x){
  list(id = format(x$id), ae = x$ae)
}

#' Check the number of articles an AE is currently working on
#'
#' This will examine the DESCRIPTION files for articles in
#' the Submissions folder, check articles that have status
#' "with AE".
#' @param articles a tibble summary of articles in the accepted and submissions folder. Output of \code{tabulate_articles()}
#' @param day_back number of day to go back for calculating AE workload.
#' @importFrom dplyr select count left_join
#' @importFrom tidyr unnest
#' @examples
#' \dontrun{
#' articles <- tabulate_articles()
#' ae_workload(articles)
#' }
#' @export
ae_workload <- function(articles, day_back = 365) {
  ae_rj <- read.csv(system.file("associate-editors.csv", package = "rj")) %>%
    select(name, initials, email)

  # Get list of current articles
  current_articles <- active_articles()

  # Only keep articles that have been handled by an AE
  # at some point
  with_AE <- filter_status(current_articles, "with AE")

  # Extract the AE line from DESCRIPTION file
  AE_assignments <- do.call("rbind", lapply(with_AE, get_AE))

  # Match initials and replace if necessary
  AE_assignments <- as.data.frame(AE_assignments)
  initials <- which(str_length(AE_assignments$ae) < 4)
  for (i in initials)
    AE_assignments$ae[i] <- ae_rj$name[ae_rj$initials == AE_assignments$ae[i]]

  # Count assignments
  AE_assignments %>% count(ae, sort=TRUE)

#  articles %>%
#    dplyr::select(id, status) %>%
#    tidyr::unnest(status) %>%
#    dplyr::filter(status == "with AE") %>%
#    dplyr::rename(ae = comments) %>%
#    dplyr::group_by(ae) %>%
#    dplyr::filter(date >= Sys.Date()- day_back) %>%
#    dplyr::count(ae) %>%
#    dplyr::left_join(ae_rj, by = c("ae" = "name"))

}

#' Add AE to the DESCRIPTION
#'
#' Fuzzy match to find the initial of the AE to fill in the article DESCRIPTION.
#' The status field is also updated with a new line of add AE.
#'
#' @param article article id
#' @param name a name used to match AE, can be AE initials, name, github handle, or email
#' @param date the date for updating status
#' @export
add_ae <- function(article, name, date = Sys.Date()){
  article <- as.article(article)

  ae_list <- read.csv(system.file("associate-editors.csv", package = "rj")) #%>%
    #mutate(concat = paste0(!!sym("name"), !!sym("github_handle"), !!sym("email")))

  found <- NA
  # Check if matches initials
  found <- which(str_detect(ae_list$initials, name))
  # If not initials, check name
  if (is.na(found))
    found <- which(str_detect(ae_list$name, name))
  # If not initials, check github
  if (is.na(found))
    found <- which(str_detect(ae_list$github, name))
  # If not initials, check email
  if (is.na(found))
    found <- which(str_detect(ae_list$email, name))

  #person <- ae_list$github[str_detect(ae_list$concat, name)]
  #person_name <- as.character(ae_list$name[str_detect(ae_list$concat, name)])

  if (!is.na(found)){
    # github start with "ae-articles-xxx"
    #ae_abbr <- str_sub(person, 13, -1)
    article$ae <- ae_list$initials[found]
    update_status(article, "with AE", comments = ae_list$name[found], date = date)

  } else {
    cli::cli_alert_warning("No AE found. Input the name as the whole or part of the AE name, github handle, or email")
  }

  return(invisible(article))
}


#' Extract corresponding author from an article
#' @param article Article id, like \code{"2014-01"}
#' @examples
#' \dontrun{
#' # extract from a single article
#' corr_author("Submissions/2020-114")
#'
#' # extract corresponding authors from the active articles
#' all <- active_articles()
#' purrr::map_dfr(all, corr_author)
#' }
#' @importFrom purrr pluck map
#' @importFrom tibble tibble
#' @export
corr_author <- function(article){

  article <- as.article(article)

  all_authors <- article$authors
  # find the index of the author that provide the email
  email <- purrr::map(1:length(all_authors), ~purrr::pluck(all_authors, .x)$email)
  idx <- which(purrr::map_lgl(email, ~!is_null(.x)))

  tibble::tibble(
    corr_author = purrr::pluck(all_authors, idx)$name,
    email = purrr::pluck(all_authors, idx)$email
  )

}
