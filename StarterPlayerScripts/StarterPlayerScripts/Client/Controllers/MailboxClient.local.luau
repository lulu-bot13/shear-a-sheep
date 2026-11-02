--[[
	The Mailbox at workspace.Base.CenterPlaza.Mailbox: its ProximityPrompt opens Roblox's built-in feedback window.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.MailboxClient
]]--

--// Services
local socialService = game:GetService("SocialService")

--// Instances
local mailboxPrompt = workspace:WaitForChild("Base")
	:WaitForChild("CenterPlaza")
	:WaitForChild("Mailbox")
	:WaitForChild("Box")
	:WaitForChild("ProximityPrompt") :: ProximityPrompt

local prompting = false

mailboxPrompt.Triggered:Connect(function()
	if prompting then
		return
	end
	prompting = true

	local success, err = pcall(socialService.PromptFeedbackSubmissionAsync, socialService)
	if not success then
		warn("Feedback prompt failed:", err)
	end
	prompting = false
end)
