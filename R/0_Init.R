#' @description Function that loads required packages or installs them if necessary
#' @param string of a package name

Package_fctn <- function(pckg) {
  if (!require(pckg, character.only = TRUE)) {
    cat("Installing required packages \n")
    install.packages(pckg, dep = TRUE, quiet = T)
  }
  require(pckg, character.only = TRUE, quietly = T)
}


#' @description Function to initialize up the project by loading, pre processing and outputting the infections data
#' @param startDate of the study
#' @param endDate of the Study
#' @param country under consideration
#' @param province under consideration
#' @param simData boolean. If TRUE, a simulated DGP is used
#' @export to the global environment a vector with the log infections, a tibble with all data and dates, a tibble with
#' all data and dates constrained to the observational period, initial value for the trend

Init_fctn <- function(model, startDate, endDate, country, province = NULL, simData = FALSE) {
  cat("Loading packages ")
  # Install and or load packages
  packages <- c(
    "Rcpp", "RcppArmadillo", "pbapply", "Matrix", "tfarima", "MCMCpack", "mvtnorm", "coda", "progress",
    "tidyverse", "readr", "lubridate", "scales", "openxlsx"
  )
  sapply(packages, Package_fctn)
  # Check the model specifications
  specs <- c(
    "UR.Seas.", "UR.Seas.C.", "UR.Seas.CVarSw.", "UR.Seas.TVarSw.", "UR.Seas.2P.TVarSw.", "UR.Seas.2P.CVarSw.",
    "UR.Seas.En.", "UR.Seas.MAC.",
    "D.Seas.", "D.Seas.C.", "D.Seas.C.3St.", "D.Seas.2P.TVarSw."
  )
  if (!(model %in% specs)) {
    stop(paste0(
      "Specification ´", model, "´ not implemented. Please select one of the following:\n",
      paste(specs, collapse = ", ")
    ))
  }
  # Load functions
  cat("\nCompiling functions\n")
  RScripts <- paste0("R/", list.files(path = paste0(getwd(), "/R")))
  RScripts <- RScripts[!str_detect(RScripts, "Models")]
  models <- list.files(path = paste0(getwd(), "/R/Models"))
  modelScripts <- paste0("R/Models/", model, "R")
  if (length(which(models == paste0("Recursions.", model, "R"))) != 0) {
    modelScripts <- append(modelScripts, paste0("R/Models/Recursions.", model, "R"))
  }
  sapply(c(RScripts, modelScripts), source)
  RcppScripts <- paste0("src/", list.files(path = paste0(getwd(), "/src")))
  sapply(RcppScripts, sourceCpp, echo = F)
  # Create a folder of the model output
  if (!dir.exists(paste0(getwd(), "/Output"))) {
    dir.create(paste0(getwd(), "/Output"))
  }
  path <- paste0(getwd(), "/Output/Output_", model)
  if (!dir.exists(path)) {
    dir.create(path)
  }
  cat("Pulling data\n")
  # Load the infection data
  jhcsseData <- read_csv("https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_global.csv",
    col_types = cols()
  )

  # Subset data specific country and province
  if (!(country %in% jhcsseData$`Country/Region`)) stop("Unknown country name")
  if (nrow(jhcsseData[jhcsseData[, "Country/Region"] == country, ]) > 1 & is.null(province)) {
    province <- deframe(jhcsseData[jhcsseData[, "Country/Region"] == country, "Province/State"])
    cat(
      "Individual analysis of the following provinces is available:\n",
      paste(province, collapse = "; "),
      "\nTo select one or multiple provinces, submit a character vector to the (province = ) argument\n"
    )
  } else if (nrow(jhcsseData[jhcsseData[, "Country/Region"] == country, ]) == 1 & !is.null(province)) {
    warning("No division into provinces available")
    province <- deframe(jhcsseData[jhcsseData[, "Country/Region"] == country, "Province/State"])
  } else if (is.null(province)) {
    province <- deframe(jhcsseData[jhcsseData[, "Country/Region"] == country, "Province/State"])
  }
  dataRaw <- jhcsseData %>%
    filter(`Country/Region` == country & `Province/State` %in% province) %>%
    dplyr::select(-c(`Country/Region`, `Province/State`, Lat, Long)) %>%
    summarise_all(sum) %>%
    pivot_longer(cols = 1:ncol(.), values_to = "C", names_to = "Date") %>%
    mutate(
      Date = mdy(Date),
      I = C - lag(C),
      logI = log(I),
      Index = 1:n()
    )
  # Subset the observational horizon
  if (max(dataRaw$Date) < endDate) {
    warning(paste(
      "End date is set to the latest available observation:",
      max(dataRaw$Date), "\n"
    ))
  }
  if (min(dataRaw$Date) > startDate) {
    warning(paste(
      "Start date is set to the earliest available observation:",
      min(dataRaw$Date), "\n"
    ))
  }

  # Output the data and important constants to the global environment
  dataTibExten <<- filter(dataRaw, Date <= endDate)
  dataTib <<- filter(dataRaw, Date >= startDate & Date <= endDate)
  dataTibTemp <- filter(dataTibExten, Date >= startDate)
  dataVecTemp <- as.matrix(dataTibTemp$logI)
  if (simData == TRUE) dataTibTemp$logI <- dataVecTemp <- simData_fctn()
  dataTib <<- dataTibTemp
  dataVec <<- dataVecTemp
  trendIni <<- dataRaw[dataRaw[, "Date"] == as.character(ymd(startDate) - 1), "logI"] %>%
    as.numeric()
  endDate <<- endDate
}
