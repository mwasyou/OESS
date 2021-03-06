<script type='text/javascript' src='js_utilities/multilink_panel.js'></script>
<script type='text/javascript' src='js_utilities/path_utils.js'></script>
<script>

function makePathTable(){
  
  var ds = new YAHOO.util.DataSource([]);
  ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
  
  var cols = [{key: "link", label: "Primary Path", width: 200}
	     ];
  
  var configs = {
    height: "337px"
  };
  
  var table = new YAHOO.widget.ScrollingDataTable("path_table", cols, ds, configs);
  
  var links = session.data.links || [];
  
  for (var i = 0; i < links.length; i++){
    table.addRow({link: links[i]});
  }
  
  return table;
}  
  
function init(){  

    session.data.circuit_type = session.data.circuit_type || 'openflow';
    session.data.links = session.data.links || [];

    setPageSummary("Path","Choose a primary path from the map below by clicking on links between nodes.");  
    if (session.data.circuit_type == 'mpls') {
        setNextButton("Proceed to Next Step: Scheduling", "?action=scheduling", verify_inputs);
    } else {
        setNextButton("Proceed to Next Step: Backup Path", "?action=backup_path", verify_inputs);
    }
  
    // Help message for MPLS path selection.
    if (session.data.circuit_type == 'openflow') {
        document.getElementById('mpls_description').style.display = 'none';
    }

  // defined in circuit_details_box.js
  var endpoint_table = summary_init();

  // yui-dt-col7 is an alias for the column of the edit
  // buttons. This was hidden on the options page due to issue
  // 160:3834, but the options page needs this for static mac
  // circuits.
  endpoint_table.hideColumn('yui-dt-col7');
  
  var path_table = makePathTable();
  
  var nddi_map = new NDDIMap("map");

  nddi_map.on("loaded", function(){
          if (session.data.circuit_type == 'mpls') {
              var url = "services/data.cgi?method=get_shortest_path";

              for (var i = 0; i < session.data.endpoints.length; i++){
                  var node = session.data.endpoints[i].node;
                  url += "&node=" + node;
              }

              //append the type
              url += "&type=" + session.data.circuit_type;

              var ds = new YAHOO.util.DataSource(url);
              ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
              ds.responseSchema = {
                  resultsList: "results",
                  fields: [
              {key: "link"}
                           ],
                  metaFields: {
                      error: "error",
                      error_text: "error_text"
                  }
              }

              ds.sendRequest("", {success: function(req, resp){


                          if (resp.meta.error){
                              alert("Error - " + resp.meta.error_text);
                              return;
                          }


                          for (var i = 0; i < resp.results.length; i++){
                              session.data.backup_links.push(resp.results[i].link);
                          }
                          this.updateMapFromSession(session);

                      },
                      failure: function(req, resp){
                          alert('Server error while determining shortest path.');
                      },
                          scope: this
                          });
          }else{

              this.updateMapFromSession(session);
          }
      });


  nddi_map.on("clickLink", function(e, args){
          onClickLink(path_table, e, args, save_session);
      });


  var layout = makePageLayout(nddi_map, {map_width: 700,
					 max_resize: 700});  

  legend_init(nddi_map);

  if (session.data.circuit_type == 'mpls') {
      session.data.backup_links = [];
      var remove_path_button = new YAHOO.widget.Button("shortest_path_button", {label: "Remove manually defined path"});
      
      remove_path_button.on("click", function(){
              var length = path_table.getRecordSet().getRecords().length;
              path_table.deleteRows(0, length);
              save_session();
          });

  }else{
  
      var shortest_path_button = new YAHOO.widget.Button("shortest_path_button", {label: "Suggest Shortest Path"});
  
      shortest_path_button.on("click", function(){
              
              this.set('disabled', true);
              this.set('label', 'Calculating shortest path...');
              
              var url = "services/data.cgi?method=get_shortest_path";
              
              for (var i = 0; i < session.data.endpoints.length; i++){
                  var node = session.data.endpoints[i].node;
                  url += "&node=" + node;
              }
              
              //append the type
              url += "&type=" + session.data.circuit_type; 
              
              var ds = new YAHOO.util.DataSource(url);
              ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
              ds.responseSchema = {
                  resultsList: "results",
                  fields: [
              {key: "link"}
                           ],
                  metaFields: {
                      error: "error",
                      error_text: "error_text"
                  }
              }
              
              ds.sendRequest("", {success: function(req, resp){
                          this.set('disabled', false);
                          this.set('label', 'Suggest Shortest Path');
                          
                          if (resp.meta.error){
                              alert("Error - " + resp.meta.error_text);
                              return;
                          }
                          
                          path_table.deleteRows(0, path_table.getRecordSet().getRecords().length);
                          
                          for (var i = 0; i < resp.results.length; i++){
                              path_table.addRow({link: resp.results[i].link});
                          }
                          
                          save_session();
                          
                      },
                          failure: function(req, resp){
                          alert('Server error while determining shortest path.');
                      },
                          scope: this
                          });
              
          });
  }
  
  function save_session(){
    
    var records = path_table.getRecordSet().getRecords();
    
    if (!session.data.hasOwnProperty('backup_links')) {
        session.data.backup_links = [];
    }

    session.data.links = [];
    
    for (var i = 0; i < records.length; i++){
      var link = records[i].getData('link');
      session.data.links.push(link);
    }
    
    session.save();

    nddi_map.updateMapFromSession(session);
  }

  
    function verify_inputs() {
        var records = path_table.getRecordSet().getRecords();

        // having no path is okay if we only have 1 node
        if (records.length < 1) {          
	    var all_same_nodes = true,
	        last_node      = "";
	

	    var endpoints = session.data.endpoints || [];

	    for (var i = 0; i < endpoints.length; i++){
	        if (last_node && last_node != endpoints[i].node){
		    all_same_nodes = false;
		    break;
	        }
	        last_node = endpoints[i].node;
	    }

            // If circuit type is not openflow we ignore path lengths of zero
	    if (!all_same_nodes && session.data.circuit_type == 'openflow') {
	        alert("You must have at least one path component.");
	        return false;
	    }
        }
    
        save_session();
    
        return true;
    }
  
}
YAHOO.util.Event.onDOMReady(init);
  
</script>
