<script>
  
function makeInterfacesTable(node){
  var node_name_holder = document.getElementById('node_name_holder');
  node_name_holder.innerHTML = "<center><h2><b>" + node + "</b></h2></center>";

    var url = "services/data.cgi?method=get_node_interfaces&node=" + encodeURIComponent(node) + "&workgroup_id=" + session.data.workgroup_id + "&show_down=1" + "&show_trunk=1";
    var ds = new YAHOO.util.DataSource(url);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
    ds.responseSchema = {
        resultsList: "results",
        fields: [
            {key: "name"},
            {key: "description"},
            {key: "status"},
            {key: "int_role"},
            {key: "vlan_tag_range"},
            {key: "mpls_vlan_tag_range"}
        ],
        metaFields: {
            error: "error"
        }
    };
  
    // tags is used to hold the available openflow vlan_tag_range;
    // This is then combined with mpls_vlan_tag_range to display a
    // list of globally valid vlans.
    var tags = '';
    var cols = [
        {key: "name", label: "Interface"},
        {key: "description", label: "Description", width: 120},
        {key: "status", label: "Status"},
        {key: "int_role", label: "Role", formatter: function(elLiner, oRec, oCol, oData) {
            if (oData === "unknown") {
                elLiner.innerHTML = "Endpoint";
            } else {
                elLiner.innerHTML = "Trunk";
            }
        }},
        {key: "vlan_tag_range", label: "Tag Range", formatter: function(elLiner, oRec, oCol, oData){
            }},
        {key: "mpls_vlan_tag_range", label: "Tag Range", formatter: function(elLiner, oRec, oCol, oData){
                var vlanTagRange;
                var mplsTagRange;
                if(oRec._oData.vlan_tag_range !== null){
                    vlanTagRange = oRec._oData.vlan_tag_range.replace(/^-1/, "untagged");
                }
                if(oRec._oData.mpls_vlan_tag_range !== null){
                    mplsTagRange = oRec._oData.mpls_vlan_tag_range.replace(/^-1/, "untagged");
                }
                var vlans;
                if(vlanTagRange !== undefined && mplsTagRange !== undefined){
                    elLiner.innerHTML = vlanTagRange + "," + mplsTagRange;
                }else if(vlanTagRange !== undefined){
                    elLiner.innerHTML = vlanTagRange;
                }else{
                    elLiner.innerHTML = mplsTagRange;
                }


            }}
    ];

    // Removes role column from table when not in 'admin' workgroup.
    // Assumes role is stored in fourth column from the left.
    if (session.data.workgroup_type !== "admin") {
        ds.responseSchema.fields.splice(3, 1);
        cols.splice(3, 1);
    }
  
    var configs = {
        height: "337px"
    };
  
    var table = new YAHOO.widget.ScrollingDataTable("add_interface_table", cols, ds, configs);
    table.hideColumn("vlan_tag_range");
    table.subscribe("rowMouseoverEvent", table.onEventHighlightRow);
    table.subscribe("rowMouseoutEvent", table.onEventUnhighlightRow);
    table.subscribe("rowClickEvent", table.onEventSelectRow);
    return table;
}
var endpoint_table;
var nddi_map;
function init(){  

  setPageSummary("Endpoints","Pick at least two endpoints from the map below.");
  
  setNextButton("Proceed to Next Step: Circuit Options", "?action=options", verify_inputs);

  if(session.data.circuit_type !== undefined){
      if(session.data.circuit_type == 'mpls'){
          setNextButton("Proceed to Next Step: Primary Path", "?action=primary_path", verify_inputs);
      }
  }
  
  endpoint_table = summary_init();

  nddi_map = new NDDIMap("map");

    var w = 540;
    if (session.data.workgroup_type === 'admin') {
        w = 470;
    }
    var layout = makePageLayout(nddi_map, {map_width: w,
                                           max_resize: 700});

  
  legend_init(nddi_map, true, false, false, true);
    
  //nddi_map.showDefault();
  
    nddi_map.on("loaded", function(){
        this.updateMapFromSession(session);
    });

    endpoint_table.subscribe("rowDeleteEvent", function(){
        if (this.getRecordSet().getLength() == 0) {
            session.data.circuit_type = undefined;
        }

        set_summary(session.data.circuit_type);
        save_session();
    });

  nddi_map.on("clickNode", function(e, args){

                var node   = args[0].name;

                var feature = args[0].feature;

                if (this.table){
                  this.table.destroy();
                  save_session();
                }

                this.changeNodeImage(feature, this.ACTIVE_IMAGE);

                this.table = makeInterfacesTable(node);

                this.table.subscribe("rowClickEvent", function(args){

            var rec = this.getRecord(args.target);
            var mpls_vlan_tag_range = rec.getData("mpls_vlan_tag_range");
            var vlan_tag_range = rec.getData("vlan_tag_range");

            var vlanTagRange;
            var mplsTagRange;
            if(rec.getData("vlan_tag_range") !== null){
                vlanTagRange = rec.getData("vlan_tag_range").replace(/^-1/, "untagged");
            }
            if(rec.getData("mpls_vlan_tag_range") !== null){
                mplsTagRange = rec.getData("mpls_vlan_tag_range").replace(/^-1/, "untagged");
            }
            var vlans;
            if(vlanTagRange !== undefined && mplsTagRange !== undefined){
                vlans = vlanTagRange + "," + mplsTagRange;
            }else if(vlanTagRange !== undefined){
                vlans = vlanTagRange;
            }else{
                vlans = mplsTagRange;
            }

            var tag_range = vlans;
            var interface = rec.getData('name');
            var description = rec.getData('description');

            var state = rec.getData('status');
            if(state == 'down'){
              alert('Creating a circuit on a link down interface may prevent your circuit from functioning');
            }

            var region = YAHOO.util.Dom.getRegion(args.target);

            var components = makeTagSelectPanel([region.left, region.bottom], {
                include_static_mac_table: true,
                panel_width: 393,
                save_action: function(options){

                    var add_row = function(options){
                        var tag           = options.tag;
                        var mac_addresses = [];
                        if(session.data.static_mac_routing) {
                            mac_addresses = options.get_mac_addresses();
                        }
                        endpoint_table.addRow({
                            interface: interface,
                            interface_description: description,
                            node: node,
                            tag: tag,
                            vlan_tag_range: rec.getData("vlan_tag_range"),
                            mac_addrs: mac_addresses 
                        });

                        set_summary(session.data.circuit_type);
                        save_session();

                        nddi_map.table.unselectAllRows();
                        nddi_map.table.vlan_panel.destroy();
                        nddi_map.table.vlan_panel = undefined; 
                    };

                    var endpoint_limit_ds = new YAHOO.util.DataSource(
                        "services/data.cgi?method=is_within_circuit_endpoint_limit"+
                        "&workgroup_id=" + session.data.workgroup_id+
                        "&endpoint_num=" + ( endpoint_table.getRecordSet().getRecords().length + 1 ) 
                    );


                    endpoint_limit_ds.responseType = YAHOO.util.DataSource.TYPE_JSON;
                    endpoint_limit_ds.responseSchema = {
                        resultsList: "results",
                        fields: [{key: "within_limit", parser: "number"}],
                        metaFields: {
                          "error": "error"
                        }
                    };

                    endpoint_limit_ds.sendRequest("",{
                        success: function(req,resp){
                            if(parseInt(resp.results[0].within_limit)){
                                add_row(options);
                            }else {
                                alert("You have exceeded this workgroups max endpoints per circuit limit");
                            }
                        },
                        failure: function(req,resp){
                            alert("Problem fetching workgroup max endpoints per circuit limit");
                        }
                    }, this);
                },
                interface: interface,
                interface_description: description,
                node: node,
                workgroup_id: session.data.workgroup_id,
                tag_range: tag_range
            });

            var vlan_input = YAHOO.util.Dom.get('new_vlan_tag');


            this.vlan_panel      = components.panel;
            var tagged           = components.tagged_input;
            var static_mac_table = components.static_mac_table;

            this.vlan_panel.show();

                        new YAHOO.util.KeyListener(vlan_input,
                    {keys: 13},
                    {fn: verify_and_add_endpoint}
            ).enable();

        });
  });
  
}

  function save_session(){
    
      var circuit_description = document.getElementById('description').value;

    var records = endpoint_table.getRecordSet().getRecords();
    session.data.bandwidth = 0;
    session.data.restore_to_primary = 0;
    session.data.static_mac_routing = 0;
    session.data.description = circuit_description;
    session.data.endpoints = [];
    
    for (var i = 0; i < records.length; i++){
      
        var node           = records[i].getData('node');
        var interface      = records[i].getData('interface');
        var description    = records[i].getData('interface_description');
        var tag            = records[i].getData('tag');
        var mac_addrs      = records[i].getData('mac_addrs');
        var vlan_tag_range = records[i].getData('vlan_tag_range');

        session.data.endpoints.push({
            interface: interface,
            node: node,
            interface_description: description,
            tag: tag,
            mac_addrs: mac_addrs,
            vlan_tag_range: vlan_tag_range
        });
    }
    
    session.save();
    
    nddi_map.updateMapFromSession(session);

  }



function verify_inputs(){

  var records = endpoint_table.getRecordSet().getRecords();
  
  if (records.length < 2){
    alert("You must have at least two endpoints.");
    return false;
  }       

  save_session();
  return true;

}
  


YAHOO.util.Event.onDOMReady(init);
  
</script>
