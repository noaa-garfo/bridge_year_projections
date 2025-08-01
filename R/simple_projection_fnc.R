#' Simple Projections for Bridge Year Estimates
#'
#' @param data data from script 01pull_and_clean_data.R
#' @param stock stock for current estimate
#' @param fishery_group fishery group or sub-component
#' @param start_date establishes date range for calculating the mean change from previous year to next. End date is two mondays before the most recent CAMS run (creates buffer for mid-week CAMS runs). For example, if CAMS run date is 7/27/2025 (a Sunday), the date range would terminate on 7/15/2024. 6 weeks is typical for the full date range. Format as 'YYYY-mm-d'
#'
#' @return value for total MT and plot of annual weekly catch + projected data
#' @export
#'
#' @examples
simple_projection <- function(data, stock, fishery_group, start_date = '2025-06-01') {

start_date <- as.Date(start_date)

cams_date <- floor_date(max(data$CAMS_RUN), "weeks", week_start = 1) - 7

proj_data <- data |>
  mutate(YEAR = as.factor(YEAR),
         FISHING_YEAR = as.factor(FISHING_YEAR),
         DOY = as.Date(paste0('2025-', DOY), format = "%Y-%m-%d"),
         WEEKDAY = wday(DATE_TRIP)) |>
  dplyr::filter(YEAR %!in% c(2020, 2026),
                DATE_TRIP < cams_date) |>
  mutate(WEEK = floor_date(DOY, "weeks", week_start = 1)) |>
  group_by(YEAR, WEEK, STOCK_ID, FISHERY_GROUP) |>
  summarise(DISCARD = sum(DISCARD),
            LANDINGS = sum(LANDINGS),
            CATCH = sum(CATCH)) |>
  ungroup() |>
  arrange(WEEK) |>
  group_by(YEAR, STOCK_ID, FISHERY_GROUP) |>
  mutate(CY_DISCARD_CUMUL = cumsum(DISCARD),
         CY_LANDING_CUMUL = cumsum(LANDINGS),
         CY_CATCH_CUMUL = cumsum(CATCH)) |>
  ungroup()


stock_data <- proj_data |>
  filter(STOCK_ID == stock, FISHERY_GROUP == fishery_group)

ACL2025 <- round(unique(filter(data, STOCK_ID == stock
                               , FISHERY_GROUP == fishery_group
                               , FISHING_YEAR == 2025)$ACL)/2204.62262, 1)

projection_data <- stock_data |>
  ungroup() |>
  select(WEEK, CATCH, YEAR) |>
  pivot_wider(names_from = YEAR, values_from = CATCH, values_fill = 0) |>
  mutate(PERC_CHANGE = (`2025`-`2024`)/`2024`)

CHANGE <- filter(projection_data, WEEK >= start_date) |>
  select(PERC_CHANGE)

CHANGE$PERC_CHANGE[is.infinite(CHANGE$PERC_CHANGE)] <- NA
CHANGE$PERC_CHANGE[is.nan(CHANGE$PERC_CHANGE)] <- NA

DIFF_MEAN <- mean(CHANGE$PERC_CHANGE, na.rm = TRUE)/100

projection <- projection_data |>
  mutate(`2025_proj` =  if_else(as.Date(WEEK) < cams_date, `2025`,
                              `2024` + (`2024` * DIFF_MEAN))) |>
  pivot_longer(-c(PERC_CHANGE, WEEK), names_to = 'YEAR', values_to = 'CATCH') |>
  mutate(CATCH = replace(CATCH, is.na(CATCH), 0)) |>
  group_by(YEAR) |>
  arrange(WEEK) |>
  mutate(CATCH_CUMUL = cumsum(CATCH)) |>
  mutate(CATCH_CUMUL = case_when(YEAR == "2025_proj" & WEEK < cams_date ~ NA,
                                 YEAR == 2025 & WEEK >= cams_date ~ NA,
                                 TRUE ~ CATCH_CUMUL))

final_catch_mt <- round(max(filter(projection, YEAR == '2025_proj')$CATCH_CUMUL, na.rm = TRUE)/2204.62262)


plot_colors <- c("2021" = "slategrey", "2022" = "orange"
                 , "2023" ="violetred",  "2024" = "turquoise4"
                 , "2025" = "black", "2025_proj" = "black" )

linetypes <- c("2021" = "solid", "2022" = "solid"
               , "2023" ="solid",  "2024" = "solid"
               , "2025" = "solid", "2025_proj" = "dotted" )


plot <- ggplot(data = projection) +
  geom_line(aes(x = WEEK, y = CATCH_CUMUL/2204.62262, colour = YEAR, group = YEAR, linetype = YEAR)) +
  scale_x_date(date_breaks = "1 month",
               date_labels = "%B") +
  geom_hline(aes(yintercept = ACL2025), color = "red") +
  labs(title = "Calendar Year Cumulative Catch", subtitle = paste0(stock, " in ", fishery_group)) +
  annotate("text", label = if_else(ACL2025 == 0, " ", "FY 2025 sub-ACL"), x = as.Date("2025-01-15"), y = ACL2025 + 1.5, size = 2) +
  ylab("Catch (MT)") +
  xlab("Day of Year") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  scale_colour_manual(values=plot_colors) +
  scale_linetype_manual(values = linetypes)

return(list(plot = plot, final_MT = final_catch_mt))
}
