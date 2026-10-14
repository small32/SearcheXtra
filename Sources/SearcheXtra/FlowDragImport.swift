import Foundation

extension FlowDrag {
    static func importConfig(_ data:Data) throws -> FlowDragConfig {
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw Invalid()}
        guard root["textDragGestures"] != nil else{let value=try JSONDecoder().decode(FlowDragConfig.self,from:data);try value.validate();return value}
        var result=FlowDragConfig();result.rules=[]
        result.enableText=root["enableTextDrag"] as? Bool ?? true;result.enableLink=root["enableLinkDrag"] as? Bool ?? true;result.enableImage=root["enableImageDrag"] as? Bool ?? true
        result.showHints=root["enableHUD"] as? Bool ?? true;result.showTrail=root["enableTrail"] as? Bool ?? false
        result.ignoreEditable=(root["textDropIgnoreInput"] as? Bool ?? true)||(root["linkDropIgnoreInput"] as? Bool ?? true)
        result.distanceThreshold=root["distanceThreshold"] as? Double ?? 20
        for object in objects {
            for imported in root[object+"DragGestures"] as? [[String:Any]] ?? [] {
                guard let pattern=imported["direction"] as? String,let action=imported["action"] as? String else{throw Invalid()}
                var fields=try JSONSerialization.jsonObject(with:JSONEncoder().encode(FlowDragRule(object:object,pattern:pattern,action:action))) as! [String:Any]
                fields.merge(imported){_,new in new};fields["object"]=object;fields["pattern"]=pattern
                if object=="image",action=="openTab" {fields["action"]="openImage"}
                if let folder=imported["folderId"] as? [String:Any] {fields["folderId"]=folder["id"] as? String ?? ""}
                let rule=try JSONDecoder().decode(FlowDragRule.self,from:JSONSerialization.data(withJSONObject:fields))
                result.rules.append(rule)
            }
        }
        try result.validate();return result
    }
}
