import 'package:flutter/material.dart';
import '../services/agent_service.dart';
import '../domain/mcp/mcp_client.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';
import 'mcp_settings_screen.dart';
class ProIntegrations extends StatefulWidget { const ProIntegrations({super.key}); @override State<ProIntegrations> createState()=>_ProIntegrationsState(); }
class _ProIntegrationsState extends State<ProIntegrations>{
 Future<List<McpServerConfig>>? _future;
 @override void initState(){super.initState();_load();}
 void _load(){_future=AgentService.instance.mcpServers();}
 @override Widget build(BuildContext context)=>Scaffold(backgroundColor:ProTheme.bgDark,appBar:ProAppBar(title:'Integrations',showAddButton:true,onAddPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const McpSettingsScreen())).then((_){if(mounted)setState(_load);})),body:Container(decoration:const BoxDecoration(gradient:ProTheme.bgGradient),child:FutureBuilder<List<McpServerConfig>>(future:_future,builder:(c,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text(s.error.toString()));final servers=s.data??[];return RefreshIndicator(onRefresh:()async{setState(_load);await _future;},child:ListView(padding:const EdgeInsets.all(16),children:[Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(gradient:ProTheme.cardGradient,borderRadius:BorderRadius.circular(14)),child:Row(children:[const Icon(Icons.hub,color:ProTheme.neonGreen),const SizedBox(width:12),Expanded(child:Text('${servers.length} MCP server configuration(s). Tool discovery verifies availability.',style:const TextStyle(color:ProTheme.textSecondary,fontSize:12)))])),const SizedBox(height:12),if(servers.isEmpty)const Padding(padding:EdgeInsets.all(30),child:Text('No MCP integrations configured yet.',textAlign:TextAlign.center,style:TextStyle(color:ProTheme.textSecondary))),...servers.map((server)=>Card(color:ProTheme.bgCard,child:ListTile(leading:const Icon(Icons.link,color:ProTheme.neonGreen),title:Text(server.name,style:const TextStyle(color:ProTheme.textPrimary)),subtitle:Text(server.endpoint,style:const TextStyle(color:ProTheme.textSecondary,fontSize:11)),trailing:const Icon(Icons.chevron_right,color:ProTheme.neonGreen),onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const McpSettingsScreen())).then((_){if(mounted)setState(_load);}))))]));} })));
}
