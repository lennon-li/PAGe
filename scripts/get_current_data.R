# scripts/get_current_data.R
# Fetches the current-season Influenza A lab-testing data from
# Public Health Ontario and prints a summary to the console.
#
# Usage:
#   Rscript scripts/get_current_data.R
#   Rscript scripts/get_current_data.R --out=results --virus="Influenza A"
#   Rscript scripts/get_current_data.R --out=results --virus="Influenza B"

args <- commandArgs(trailingOnly = TRUE)
get_kv <- function(prefix, default = NULL) {
  hit <- grep(paste0("^", prefix, "="), args, value = TRUE)
  if (length(hit) == 0L) return(default)
  sub(paste0("^", prefix, "="), "", hit[[1L]])
}

out_dir  <- get_kv("--out",   "results")
virus    <- get_kv("--virus", "Influenza A")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n=== get_current_data.R ===\n")
cat("virus:  ", virus,   "\n")
cat("out:    ", out_dir, "\n\n")

# ---- load required packages ----
for (pkg in c("dplyr", "MMWRweek", "lubridate", "ggplot2", "scales")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop("Required package not installed: ", pkg)
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

# ---- source getCurrentD from the project R/ directory ----
r_file <- file.path("R", "getCurrentD.R")
if (!file.exists(r_file)) stop("Cannot find R/getCurrentD.R")
source(r_file, local = FALSE)

# ---- call getCurrentD() ----
cat("Calling getCurrentD(virus = \"", virus, "\") ...\n", sep = "")
currentD <- tryCatch(
  getCurrentD(virus = virus),
  error = function(e) {
    cat("ERROR fetching data:\n  ", conditionMessage(e), "\n")
    quit(save = "no", status = 1)
  }
)

# ---- show results ----
cat("\n--- Data summary ---\n")
cat("Rows:    ", nrow(currentD), "\n")
cat("Columns: ", paste(names(currentD), collapse = ", "), "\n")
cat("Seasons: ", paste(sort(unique(currentD$season)), collapse = ", "), "\n")
cat("Weeks:   ", min(currentD$week, na.rm = TRUE), "to",
    max(currentD$week, na.rm = TRUE), "\n")
cat("Date range: ", format(min(currentD$date, na.rm = TRUE)),
    "to", format(max(currentD$date, na.rm = TRUE)), "\n\n")

cat("--- Full data ---\n")
print(as.data.frame(currentD), digits = 4)

# ---- save ----
out_csv <- file.path(out_dir, "current_data.csv")
write.csv(currentD, out_csv, row.names = FALSE)
cat("\nSaved: ", out_csv, "\n")

# ---- plot ----
cat("\nBuilding plot...\n")

# One colour per season, most-recent season drawn on top
seasons_ordered <- sort(unique(currentD$season))
n_seasons       <- length(seasons_ordered)
season_colours  <- setNames(
  scales::hue_pal()(n_seasons),
  seasons_ordered
)
# Make the current (last) season stand out
season_colours[seasons_ordered[n_seasons]] <- "#D7191C"

p_plot <- ggplot(currentD,
                 aes(x = date, y = p,
                     colour = season, group = season)) +
  # bar chart of raw counts underneath
  geom_col(aes(y = y / max(currentD$N, na.rm = TRUE) * 0.25,
               fill = season),
           alpha = 0.15, width = 5, show.legend = FALSE) +
  # smooth trend lines for context seasons
  geom_line(data = subset(currentD,
                          season != seasons_ordered[n_seasons]),
            linewidth = 0.7, alpha = 0.55) +
  geom_point(data = subset(currentD,
                           season != seasons_ordered[n_seasons]),
             size = 1.5, alpha = 0.55) +
  # current season on top, bolder
  geom_line(data = subset(currentD,
                          season == seasons_ordered[n_seasons]),
            linewidth = 1.4) +
  geom_point(data = subset(currentD,
                           season == seasons_ordered[n_seasons]),
             size = 2.5) +
  scale_colour_manual(values = season_colours) +
  scale_fill_manual(values = season_colours) +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 0.1),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_x_date(date_breaks = "1 month", date_labels = "%b %Y") +
  labs(
    title    = paste0(virus, " — Weekly % Positivity"),
    subtitle = paste0("Seasons: ",
                      paste(seasons_ordered, collapse = ", ")),
    x        = "Date",
    y        = "% Positive",
    colour   = "Season",
    caption  = paste0("Source: Public Health Ontario ORVT\n",
                      "Generated: ", format(Sys.Date()))
  ) +
  theme_bw(base_size = 12) +
  theme(
    legend.position  = "bottom",
    axis.text.x      = element_text(angle = 45, hjust = 1),
    plot.title       = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

out_png <- file.path(out_dir, "current_data_plot.png")
ggsave(out_png, plot = p_plot, width = 10, height = 5.5,
       dpi = 150, bg = "white")
cat("Saved: ", out_png, "\n")
cat("DONE\n")
