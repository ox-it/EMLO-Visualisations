## ================================================================================
## This work is distributed under the MIT license, included in the parent directory
## Copyright Owner: University of Oxford
## Date of Authorship: 2016
## Author: Martin John Hadley (orcid.org/0000-0002-3039-6849)
## Academic Contact: Arno Bosse (http://orcid.org/0000-0003-3681-1289)
## Data Source: emlo.bodleian.ox.ac.uk
## ================================================================================

## ================================================================================
## ===================== Select Three Individuals Network =========================


### ====================================== Select Individuals ==============================
### ========================================================================================

output$select_individuals_ui <- renderUI({
  people_with_connections <- people_with_connections()
  
  selectizeInput(
    "select_individuals",
    label = "Select Individuals",
    choices = people_with_connections,
    # selected = as.character(people_with_connections[1]),
    multiple = TRUE,
    width = "100%",
    options = list(
      maxItems = 3,
      placeholder = 'Please select at least one individual by typing their name here...',
      onInitialize = I('function() { this.setValue("empty"); }')
    )
  )
})

### ====================================== Time Filters etc   ==============================
### ========================================================================================

output$visNetwork_selected_individuals_show_timeslider_UI <-
  renderUI({
    checkboxInput(
      "visNetwork_selected_individual_show_timeslider",
      label = "Remove undated interactions and filter by date?",
      value = FALSE
    )
  })


output$visNetwork_selected_individuals_time_period_of_interest_UI <-
  renderUI({
    if (is.null(input$visNetwork_selected_individual_show_timeslider)) {
      return()
    }
    if (input$visNetwork_selected_individual_show_timeslider == TRUE) {
      dates <-
        c(multiparty.interactions$DateOne.Year,
          multiparty.interactions$DateTwo.Year)
      dates <- dates[!is.na(dates)]
      
      # Remove an incorrect date
      dates <- dates[dates > 1000]
      
      sliderInput(
        "visNetwork_selected_individual_time_period_of_interest",
        "Time period of interest:",
        min = as.POSIXct(paste0(min(dates) - 1, "-01-01")),
        max = as.POSIXct(paste0(max(dates), "-01-01")),
        step = 1,
        value = as.POSIXct(c(
          paste0(min(dates), "-01-01"), paste0(max(dates), "-01-01")
        )),
        timeFormat = "%Y"
      )
    }
  })

output$neighbor_degree_UI <- renderUI({
  if (is.null(input$visNetwork_selected_individual_show_timeslider)) {
    return()
  }
  sliderInput(
    "neighbor.degree",
    label = "Neighbour Degree",
    min = 1,
    max = 3,
    value = 1,
    step = 1
  )
})


### ====================================== Generate Network Data =====================================
### ==================================================================================================

network_edges <- reactive({
  network.edges.function(filter_interactions())
})

visNetwork_select_individuals_nodes <- reactive({
  if (is.null(input$select_individuals)) {
    return()
  }
  
  ## Set selected.interactions as all multiparty.interactions
  selected.interactions <- filter_interactions()
  
  ## Apply network.edges.function to selected.interactions
  edges <- network_edges()
  ## Get nodes from edges
  nodes.of.network <-
    unique(c(edges$Primary.Emlo_ID, edges$Secondary.Emlo_ID))
  
  ## Only include individuals in the people.df data set
  nodes <- subset(people.df, iperson_id %in% nodes.of.network)
  
  visNetwork_nodes <- data.frame(
    "Person.Name" = nodes$Person.Name,
    "Surname" = nodes$Surname,
    "emlo_id" = nodes$iperson_id,
    "color" = rep("lightblue", nrow(nodes))
  )
  ## Return for use
  
  visNetwork_nodes
})

visNetwork_select_individuals_edges <- reactive({
  ## Set selected.interactions as all multiparty.interactions
  selected.interactions <- filter_interactions()
  
  ## Apply network.edges.function to selected.interactions
  edges <- network_edges()
  ## Get nodes from edges
  nodes.of.network <-
    unique(c(edges$Primary.Emlo_ID, edges$Secondary.Emlo_ID))
  
  ## Subset people.df by nodes in edges
  nodes <- subset(people.df, iperson_id %in% nodes.of.network)
  
  visNetwork_edges <-
    data.frame(
      "source" = as.numeric(
        mapvalues(
          edges$Primary.Emlo_ID,
          from = nodes$iperson_id,
          to = 0:(nrow(nodes) - 1),
          warn_missing = FALSE
        )
      ),
      "target" = as.numeric(
        mapvalues(
          edges$Secondary.Emlo_ID,
          from = nodes$iperson_id,
          to = 0:(nrow(nodes) -
                    1),
          warn_missing = FALSE
        )
      ),
      "source.emlo.id" = as.numeric(edges$Primary.Emlo_ID),
      "target.emlo.id" = as.numeric(edges$Secondary.Emlo_ID),
      "value" = 20 * edges$Total.Connections,
      "width" = rescale(20 * edges$Total.Connections, to = c(4, 12)),
      "EdgeColor" = rep("lightblue", nrow(edges))
    )
  
  ## return for use
  visNetwork_edges
})

### ====================================== Find Connected Subgrapgh ========================
### ========================================================================================

visNetwork_select_individuals_neighboring_nodes <- reactive({
  if (is.null(input$select_individuals)) {
    return()
  }
  
  edges <- visNetwork_select_individuals_edges()
  
  edges <- edges[, c("source.emlo.id", "target.emlo.id")]
  ## Extract nodes
  nodes <- unique(c(edges$source.emlo.id, edges$target.emlo.id))
  
  ## Generate igraph
  igraph.for.computation <-
    graph.data.frame(edges, nodes, directed = FALSE)
  
  # ## plot igraph
  # # plot(igraph.for.computation, vertex.size=2, vertex.label=NA, edge.arrow.size=.2)
  #
  # ## Set graph.union.passed to TRUE
  graph.union.passed <<- TRUE
  
  ## Use tryCatch for errors when no connected edges found!
  tryCatch(
    visNetwork_select_individuals_neighboring_nodes <-
      ## Find neihbouring nodes, graph.union is needed as make_ego_graph outputs a list of graph
      graph.union(
        make_ego_graph(
          igraph.for.computation,
          order = input$neighbor.degree,
          nodes = input$select_individuals
        )
      ),
    error = function(e) {
      graph.union.passed <<- FALSE
    }
  )
  if (!graph.union.passed) {
    graph.union.passed <<- FALSE
    graph.union.passed
  } else
    visNetwork_select_individuals_neighboring_nodes
})

subgraph_members <- reactive({
  # plot igraph of neighboring vertices
  # plot(visNetwork_select_individuals_neighboring_nodes,vertex.size=2, vertex.label=V(visNetwork_select_individuals_neighboring_nodes)$name, edge.arrow.size=.2)
  
  if (is.null(visNetwork_select_individuals_neighboring_nodes())) {
    return()
  }
  
  if (is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    visNetwork_select_individuals_neighboring_nodes <-
      visNetwork_select_individuals_neighboring_nodes()
    
    ## Subset multiparty.interactions by the node names:
    selected.interactions <-
      subset(
        multiparty.interactions,
        Primary.Participant.Emlo_ID %in% V(visNetwork_select_individuals_neighboring_nodes)$name &
          Secondary.Participant.Emlo_ID %in% V(visNetwork_select_individuals_neighboring_nodes)$name
      )
    ## return
    selected.interactions
  }
})

subgraph_edges <- reactive({
  ## Generates edges for visNetwork
  visN_edges <- network.edges.function(subgraph_members())
  
  ## Return dataframe
  visN_edges
})

### ====================================== Details of excluded data ========================
### ========================================================================================


output$selected_individual_NumberOfExcluded <- renderUI({
  if (is.null(input$visNetwork_selected_individual_show_timeslider)) {
    return()
  }
  
  if (is.null(input$select_individuals)) {
    return()
  }
  
  selected.interactions <- filter_interactions()
  
  multiparty.people <-
    unique(
      c(
        multiparty.interactions$Primary.Participant.Emlo_ID,
        multiparty.interactions$Secondary.Participant.Emlo_ID
      )
    )
  
  selected.people <-
    unique(
      c(
        selected.interactions$Primary.Participant.Emlo_ID,
        selected.interactions$Secondary.Participant.Emlo_ID
      )
    )
  
  visN_edges <- subgraph_edges()
  
  ## Subset people.df by the nodes appearing in the edges:
  visN_nodes <-
    subset(people.df, iperson_id %in% unique(
      c(visN_edges$Primary.Emlo_ID, visN_edges$Secondary.Emlo_ID)
    ))
  
  if (is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    HTML(
      paste0(
        "<p>Included Interactions: ",
        nrow(visN_edges),
        "</p>",
        "<p>Included People/Organisations: ",
        nrow(visN_nodes),
        "</p>",
        "<p>Excluded Interactions: ",
        nrow(multiparty.interactions) - nrow(visN_edges),
        "</p>",
        "<p>Excluded People/Organisations: ",
        length(multiparty.people) - nrow(visN_nodes),
        "</p>"
      )
    )
  }
  
  
})

### ====================================== Generate visNetwork ========================
### ========================================================================================

## show warning if no edges to display
output$selected.individual.network_no_graph <- renderUI({
  ## If not loaded yet, stop
  
  if (input$visNetwork_selected_individual_show_timeslider &
      is.null(input$visNetwork_selected_individual_time_period_of_interest)) {
    wellPanel()
  }
  
  if (is.null(input$select_individuals)) {
    wellPanel(
      "Please select at least one individual from the Cultures of Knowledge network by typing into the 'Select Individuals' field."
    )
  }
  
  if (is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    return()
  } else {
    wellPanel(HTML(
      paste0(
        "<p>",
        "This visualisation is designed to depict a 'subgraph' containing all of the selected individuals above.",
        "</p>",
        "<p>",
        "The current filter settings mean that such a network cannot be generated from data currently available from EMLO.",
        "</p>",
        "<p>",
        "It is likely that you have enabled the time filter for the network and one (or more) of the individuals are only connected ",
        "to others with (currently) undated interactions.",
        "</p>"
      )
    ))
  }
  
})

## Show connections between selected individuals
output$select.individual.network_graph <- renderVisNetwork({
  ## If not loaded yet, stop
  if (is.null(input$select_individuals)) {
    return()
  }
  
  ## if timeslider is to be shown but the controller variable is null do not return anything
  if (input$visNetwork_selected_individual_show_timeslider &
      is.null(input$visNetwork_selected_individual_time_period_of_interest)) {
    return()
  }
  
  # if (input$visNetwork_selected_individuals_show_timeslider &
  #     is.null(input$visNetwork_selected_individuals_time_period_of_interest)) {
  #   return()
  # }
  
  if (!is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    return()
  }
  
  ## load visN_edges
  visN_edges <- subgraph_edges()
  
  ## If graph.union.passed is FALSE then the visN_edges is null
  if (is.null(visN_edges)) {
    return()
  }
  
  visN_edges <- data.frame(
    "from" = visN_edges$Primary.Emlo_ID,
    "to" = visN_edges$Secondary.Emlo_ID,
    stringsAsFactors = FALSE
  )
  
  ## Subset people.df by the nodes appearing in the edges:
  visN_nodes <-
    subset(people.df, iperson_id %in% unique(c(visN_edges$from, visN_edges$to)))
  
  ## Pull out data for visNetwork
  visN_nodes <- data.frame(
    "id" = visN_nodes$iperson_id,
    "title" = visN_nodes$Person.Name,
    "label" = visN_nodes$Surname,
    "color" = mapvalues(
      visN_nodes$iperson_id %in% non_people_in_people_df,
      from = c(TRUE, FALSE),
      to = c("#a1d76a", "#7570b3")
    ),
    "group" = mapvalues(
      visN_nodes$iperson_id %in% non_people_in_people_df,
      from = c(TRUE, FALSE),
      to = c("O", "P")
    ),
    "font.size" = 20,
    stringsAsFactors = F
  )
  
  ## Highlight the selected nodes as red
  node_colors <- visN_nodes$color
  node_colors[match(input$select_individuals, visN_nodes$id)] <-
    "red"
  
  ## Highlight first degree edges as red
  edge_colors <-
    mapvalues(
      visN_edges$from %in% input$select_individuals |
        visN_edges$to %in% input$select_individuals,
      from = c(TRUE, FALSE),
      to = c("#d95f02", "#7570b3")
      # to = c("#d95f02", "lightblue")
    )
  visN_edges$color <- edge_colors
  
  visN_nodes$color <- node_colors
  ## Remove duplicated nodes
  visN_nodes <- visN_nodes[!duplicated(visN_nodes$id), ]
  
  ## Drop edges with nodes not in the node list
  non.conflicting.nodes <-
    intersect(unique(c(visN_edges$from, visN_edges$to)), visN_nodes$id)
  visN_edges <-
    subset(visN_edges,
           from %in% non.conflicting.nodes &
             to %in% non.conflicting.nodes)
  
  ## Legend nodes
  lnodes <-
    data.frame(
      label = c("Person", "Organisation", "Selected Person"),
      shape = c("icon", "icon", "icon"),
      icon.code = c("f007", "f0c0", "f007"),
      icon.color = c("#7570b3", "#a1d76a", "red"),
      icon.size = c(48, 24, 48),
      id = 1:3
    )
  
  ## Visualise
  visNetwork(visN_nodes, visN_edges) %>%
    visNodes(color = list(border = "darkblue"),
             size = 15) %>%
    visIgraphLayout() %>%
    visInteraction(
      tooltipDelay = 0.2,
      hideEdgesOnDrag = FALSE,
      dragNodes = FALSE,
      dragView = TRUE,
      zoomView = TRUE
    ) %>%
    visOptions(highlightNearest = TRUE) %>%
    visLayout(hierarchical = FALSE) %>%
    addFontAwesome() %>%
    visGroups(groupname = "O", color = "#a1d76a") %>%
    visGroups(groupname = "P", color = "#7570b3") %>%
    visLegend(addNodes = lnodes, useGroups = FALSE) %>%
    # addFontAwesome() %>%
    # visLegend(addNodes = list(
    #   list(label = "Group", shape = "icon", icon = list(code = "f0c0", size = 25)),
    #   list(label = "User", shape = "icon", icon = list(code = "f007", size = 50))
    # ), useGroups = FALSE) %>%
    visEvents(selectNode = "function(nodes) {
              Shiny.onInputChange('current_node_id', nodes);
              ;}")
  
  
  })

# observe({
#   if (is.null(input$highlighted.node)) {
#     return()
#   }
#
#   if (input$highlighted.node != "None") {
#     visNetworkProxy("visNetwork_wholeNetwork") %>%
#       visFocus(id = input$highlighted.node, scale = 1) %>%
#       visUpdateNodes(nodes = data.frame("id" = input$highlighted.node,
#                                         "color" = "red"))
#   } else {
#     visNetworkProxy("visNetwork_wholeNetwork") %>% visFit(nodes = NULL)
#   }
#
# })

output$select.individual.network_graph_UI <- renderUI({
  if (is.null(input$select_individuals)) {
    return()
  }
  
  ## if timeslider is to be shown but the controller variable is null do not return anything
  if (input$visNetwork_selected_individual_show_timeslider &
      is.null(input$visNetwork_selected_individual_time_period_of_interest)) {
    return()
  }
  
  if (!is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    return()
  }
  
  wellPanel(visNetworkOutput("select.individual.network_graph"))
})

### ====================================== Selected Individuals =====================================
### ==================================================================================================

output$visNetwork_select_individual_selected_node_info <- renderUI({
  if (is.null(input$current_node_id)) {
    return()
  }
  
  if (!is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    return()
  }
  
  selected.person.name <-
    people.df[people.df$iperson_id == as.numeric(input$current_node_id$nodes[[1]]), "Person.Name"]
  selected.person.name <-
    selected.person.name[!is.na(selected.person.name)]
  
  selected_emlo_id <-
    as.numeric(input$current_node_id$nodes[[1]])
  
  # Load connected individuals
  connected_life_events <- subgraph_members()
  
  connected_life_events <- connections_to_selected_individual()
  connected_life_events <-
    connected_life_events[!duplicated(connected_life_events),]
  
  wellPanel(HTML(
    paste0(
      "<p><strong>Selected Person: ",
      "<a target='_blank' href=http://emlo.bodleian.ox.ac.uk/profile?type=person&id=",
      selected_emlo_id,
      ">",
      selected.person.name,
      "</a></strong></p>",
      "<p>Number of Unique Connections: ",
      nrow(connected_life_events),
      "</p>",
      "<p>Scroll down for more information about ",
      trimws(selected.person.name),
      "'s connections.",
      "</p>",
      sep = ""
    )
  ))
  
})


output$visNetwork_selected_individual_connected_life_events_columns_to_show_UI <-
  renderUI({
    if (!is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
      return()
    }
    
    fluidRow(column(
      selectInput(
        'connected_life_events_Cols',
        'Columns to show:',
        usefulCols_life_events,
        selected = c(
          "Primary.Participant.Name",
          "Secondary.Participant.Name",
          "Category",
          "Event.or.Relationship.Type",
          "Primary.Participant.Role",
          "Secondary.Participant.Role",
          "DateOne.Year",
          "DateTwo.Year",
          "Date.Type",
          "Location.Type.Ahead"
        ),
        multiple = TRUE,
        width = "100%"
      ),
      width = 12
    ))
  })

connections_to_selected_individual <- reactive({
  if (is.null(input$current_node_id)) {
    return()
  }
  
  if (!is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    return()
  }
  
  ## Set subgraph_members as all multiparty.interactions
  subgraph_members <- subgraph_members()
  
  # Drop levels that are empty (as a result of above subsetting)
  subgraph_members <- droplevels(subgraph_members)
  
  # Append a column with the URLS
  
  ## Get selected individual from click
  selectedIndividual <-
    as.numeric(input$current_node_id$nodes[[1]])
  
  selected_emlo_id <-
    as.numeric(input$current_node_id$nodes[[1]])
  
  # Get edges of network
  edges <- subgraph_edges()
  
  connectedIndividuals <-
    c(as.character(edges[edges$Primary.Emlo_ID == selectedIndividual, "Primary.Emlo_ID"]),
      as.character(edges[edges$Secondary.Emlo_ID == selectedIndividual, "Secondary.Emlo_ID"]))
  
  connections_to_selected_individual <-
    subgraph_members[subgraph_members$Primary.Participant.Emlo_ID == selectedIndividual |
                       subgraph_members$Secondary.Participant.Emlo_ID == selectedIndividual, ]
  
})

connected_individuals_events <- reactive({
  if (!is.igraph(visNetwork_select_individuals_neighboring_nodes())) {
    return()
  }
  
  # Load connected individuals
  connected_life_events <- connections_to_selected_individual()
  
  connected_life_events$Primary.Participant.Name <-
    paste0(
      "<a target='_blank' href=http://emlo.bodleian.ox.ac.uk/profile?type=person&id=",
      connected_life_events$Primary.Participant.Emlo_ID,
      ">",
      connected_life_events$Primary.Participant.Name,
      "</a>"
    )
  
  connected_life_events$Secondary.Participant.Name <-
    paste0(
      "<a target='_blank' href=http://emlo.bodleian.ox.ac.uk/profile?type=person&id=",
      connected_life_events$Secondary.Participant.Emlo_ID,
      ">",
      connected_life_events$Secondary.Participant.Name,
      "</a>"
    )
  
  # Drop empty rows:
  connected_life_events <-
    connected_life_events[!!rowSums(!is.na(connected_life_events)), ]
  # Return only selected columns
  connected_life_events <-
    connected_life_events[, input$connected_life_events_Cols, drop = FALSE]
  # Replace "." with " " in colnames
  colnames(connected_life_events) <-
    gsub("[.]", " ", colnames(connected_life_events))
  # Convert factors to characters for sorting:
  factor_columns <- sapply(connected_life_events, is.factor)
  connected_life_events[factor_columns] <-
    lapply(connected_life_events[factor_columns], as.character)
  
  # Find position of names to make these columns non-orderable
  name_columns <-
    which(
      colnames(connected_life_events) %in% c("Primary Participant Name", "Secondary Participant Name")
    )
  
  # Return to datatable
  connected_life_events
})

fixed_order_columns <-
  c("Primary Participant Name",
    "Secondary Participant Name",
    "Category")

output$visNetwork_selected_individual_selected_node <-
  DT::renderDataTable({
    print(colnames(connected_individuals_events()))
    
    connected_individuals_events <- connected_individuals_events()
    cols_names <- colnames(connected_individuals_events)
    
    connected_individuals_events[, c(fixed_order_columns, cols_names[!cols_names %in% fixed_order_columns])]
    
    
  }, escape = FALSE,
  rownames = FALSE,
  # filter = list(position = 'top', clear = FALSE)
  options = list(order = list(list(0, "desc")))
  # only make name column non-orderable
  # options = if (length(which(
  #   colnames(connected_individuals_events()) %in% c("Primary Participant Name", "Secondary Participant Name")
  # )) > 0) {
  #   list(
  #     dom = 'ft',
  #     columnDefs = list(list(
  #       targets = which(
  #         colnames(connected_individuals_events()) %in% c("Primary Participant Name", "Secondary Participant Name")
  #       ) - 1,
  #       orderable = FALSE
  #     )),
  #     search = list(regex = TRUE,
  #                   caseInsensitive = FALSE),
  #     order = list(list(2,"desc"))
  #   )
  # }
  )
